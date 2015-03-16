package GitWeb;
use English;
use FindBin qw/  $Bin /;
use File::Basename qw/ dirname basename /;
use File::Find::Rule;
use IPC::System::Simple qw/system systemx capture capturex run runx $EXITVAL EXIT_ANY/;
use feature 'say';
use File::HomeDir;
use Dancer2;
use Try::Tiny;
#use Git;
use Template;
use Sys::Hostname;
use Data::Dumper::Hash;
my $login = getlogin || getpwuid($<);
my $hostname = hostname;

our $VERSION = '0.1';

my $gitpath = config->{'gitpath'};
my $repodir = config->{'repodir'};
my $home = File::HomeDir->my_home;
my $gitolite_admin = "$home/gitolite-admin";
my $gitolite_conf = "${gitolite_admin}/conf/gitolite.conf";
my $gitoweb_cfg = dirname($Bin)."/gitoweb.cfg";
our $config;
unless (-f $gitoweb_cfg) {
    $config = { users => {},
               repos => {},
               projects => {},
               groups => { all => {} },
               sshkeys => {},
           };
    save_config();
}
load_config();
set session_dir => dirname($Bin).'/sessions';


hook before => sub {
	unless (-d $gitolite_admin ) {
        debug "\$gitolite_admin $gitolite_admin doesn't exist";
		initial_setup();
	}
#	if (!session('user') && request->dispatch_path !~ m{^/(login|register)}) {
#		# Pass the original path requested along to the handler:
#		forward '/login', { requested_path => request->dispatch_path };
#	}
};

get '/' => sub {
	load_config();
#	reconfig_gitolite();
    template 'index', { config => $config };
};
get '/docs' => sub {
    send_file 'index.html';
};


get '/reset' => sub {
	reset_it();
	redirect '/';
};

get '/setup' => sub {
	initial_setup();
    get_gitolite_config();
	forward '/';
};
get '/users' => sub {
    template 'useradmin', { config => $config };
};
get '/login' => sub {
    template 'login', { config => $config, path => vars->{requested_path} };
};
post '/login' => sub {
    chomp params->{pass};
    unless (Exists($config->{users}, params->{user}) and $config->{users}{ params->{user} }{Password} eq params->{pass}) {
        redirect '/login?failed=1';
    }
    else {
        session user => params->{user};
        redirect params->{requested_path} || '/';
    }
};
get '/register' => sub {
    template 'register';
};
post '/register' => sub {
	debug "post register for ".params->{user};
	debug Dump(user => params->{user},
						     pass => params->{pass});
    unless (params->{user} and params->{pass}) {
		debug "No user or pass supplied";
        redirect '/register';
    }
    if (Exists($config->{users}, params->{user})) {
        redirect '/register?failed=1';
    }
	debug "insert ".params->{user};
    $config->{users}{ params->{user} }{Password} = crypt params->{pass}, __PACKAGE__;
    save_config();
    my $output = Data::Dumper->Dump([params->{user}, $config], [qw/$user $config/]);
    debug $output;
    session user => params->{user};
    redirect '/';
};

any '/logout' => sub {
    session->delete(session('user'));
    template 'login';
    redirect '/login';
};
get '/project/:project' => sub {
	template 'project', { config => $config, project => params->{project} };
};

get '/projects' => sub {
	template 'projects', { projects => $config->{projects}, error => params->{error} };
};
get '/newproject' => sub {
     template 'newproject', { error => params->{error} };
};
post '/newproject' => sub {
    unless (params->{name}) {
        redirect "/newproject?error=Mandatory param Name not supplied";
    }
    unless (params->{desc}) {
        redirect "/newproject?error=Mandatory param Description not supplied";
    }
    if (Exists($config->{projects}, params->{name})) {
        redirect '/newproject?error=Project already exists';
    }
    debug "making project in ".params->{name};
    $config->{projects}{params->{name}} = { name => params->{name},
                                            desc => params->{'desc'},
                                            repos => {},
                                        };
    save_config();
    redirect '/';

};
get '/newrepo' => sub {
    my $output = Data::Dumper->Dump([$config], [qw/$config/]);
    debug "before newrepo $output";
    template 'newrepo', {  projects => $config->{projects}, error => params->{'error'}  };
};
get '/newrepo/:project' => sub {
    template 'newrepo', {  projects => $config->{projects}, currentproject => params->{project}, error => params->{'error'}  };
};
post '/newrepo' => sub {
	my %params = params;
	debug Dump(params=> \%params);
    unless (params->{name}) {
        redirect '/newrepo?error="Mandatory param Name not supplied"';
    }
    unless (params->{desc}) {
        redirect '/newrepo?error="Mandatory param Description not supplied"';
    }
    if (Exists($config->{projects}, params->{'name'})) {
        redirect '/newproject?error="Repository already exists"';
    }
    my $output = Data::Dumper->Dump([$config, ], [qw/$config/]);
    debug "before newrepo $output";
    $config->{repos}{ params->{'name'} } = {
                                                'RW+' => { '@all' => '@all' },
                                                name => params->{'name'},
                                                project => params->{'project'},
                                                description => params->{'desc'},
                                                is_public => params->{public},
                                               };
    $config->{projects}{ params->{'project'} }{repos}{ params->{'name'} } = { 
                                                                 name => params->{'name'},
                                                                 description => params->{'desc'},
                                                                 is_public => params->{public}
                                                             };

    save_config();
	reconfig_gitolite();
    $output = Data::Dumper->Dump([$config, ], [qw/$config/]);
    debug "after newrepo $output";
	redirect '/';

};
get '/repo/:project/:repo' => sub {
    get_repo_details(params->{'project'}, params->{'repo'});
	template 'repo', { config => $config, project => params->{'project'}, repo => params->{'repo'} };
};
get '/sshkeys' => sub {
	template 'sshkeys', { sshkeys => $config->{sshkeys} }; #, { layout => undef };
};
get '/file/:project/:repo/:file' => sub {
    template 'file', {config => $config, project => params->{'project'}, repo => params->{'repo'}, file =>  params->{'file'}};
};
get '/addsshkey' => sub {
	template 'addsshkey';
};
get '/save' => sub {
    load_config();
    reconfig_gitolite();
	redirect '/';
};
post '/addsshkey' => sub {
	my %params = params;
	debug Dump(params=> \%params);
    if (Exists($config->{sshkeys}, params->{'keyname'})) {
           redirect '/addsshkey?error=key already exists';
    }
    else {
        $config->{sshkeys}{ params->{'keyname'} } = params->{'sshkey'};
		my $gitolite_keydir = "$home/gitolite-admin/keydir";
		my $keyfile = join("/",$gitolite_keydir, params->{'keyname'}.".pub");
		my $fh;
		chdir("$home/gitolite-admin");

		$fh = new FileHandle ">$keyfile" or error "can't write $keyfile: $!";
		$fh->print(params->{'sshkey'});
		$fh->close;
		system("git add $keyfile");
		system(qq!git commit -m "added $keyfile"!);
        save_config();
		reconfig_gitolite();
		system(qq!git push"!);
	}
	redirect '/sshkeys';
};
sub reconfig_gitolite {
	my @changes = ();
	my $processed = template 'gitolite.conf', { config => $config, env => \%ENV }, {layout => 0 };
	debug "processed = ".$processed;
	my $fh = new FileHandle "> $gitolite_conf" or die "Whoops: can't write to $gitolite_conf: $!";
	$fh->print($processed);
	$fh->close;
	push(@changes,  "conf/gitolite.conf");
	chdir $gitolite_admin;
	system("git add conf/gitolite.conf");
	system(qq!git commit -m "changed !.join("\n", @changes).'"');
	system("git push -f");

}
sub reset_it {
	debug "resetting";
	foreach my $what (qw!bin/* gitolite-admin gitolite gitoweb/gitoweb.cfg repositories projects.list *.pub .gitolite* .ssh/* sessions!) {
		debug "rm -rf $home/$what";
		my $fh = new FileHandle "rm -rf $home/$what 2>&1|";
		while (my $line = <$fh>) {
			debug $line;
		}
	}
}
sub initial_setup {
	unless (-d $gitolite_admin ) {
		chdir $home;
        $ENV{GIT_SSL_NO_VERIFY}="true";
        debug "/opt/app/murex/SEB/bin/git clone https://github.com/sitaramc/gitolite.git";
        try {
            system("/opt/app/murex/SEB/bin/git clone https://github.com/sitaramc/gitolite.git");
        };
        if (-e "$home/.ssh/gitolite") {
            debug "rm -rf $home/.ssh/id_rsa";
            system("rm -rf $home/.ssh/id_rsa");
        }
		say(qq!ssh-keygen -b 2048 -t rsa -f .ssh/id_rsa -P "" -q!);
		system(qq!ssh-keygen -b 2048 -t rsa -f .ssh/id_rsa -P "" -q!);
		my $fh = new FileHandle "> $home/.ssh/config";
		$fh->print("Host *\n\tStrictHostKeyChecking no\n");
		$fh->close;
	}
	unless (-d  "$home/bin") {
		mkdir("$home/bin");
    }
		say(qq!$home/gitolite/install -to $home/bin!);
		system(qq!$home/gitolite/install -to $home/bin!);
		say(qq!$home/bin/gitolite setup -pk  $home/.ssh/id_rsa.pub!);
		system(qq!$home/bin/gitolite setup -pk  $home/.ssh/id_rsa.pub!);
		chdir $home;
        unless (-d "${home}/gitolite-admin" ) {
    my $user = (getpwuid($EUID))[0];
    debug qq!/opt/app/murex/SEB/bin/git clone ${user}\@${hostname}:gitolite-admin!;
    system(qq!/opt/app/murex/SEB/bin/git clone ${user}\@${hostname}:gitolite-admin!);
    }
}
sub get_gitolite_config {
    my $output = Data::Dumper->Dump([$config], [qw/$config/]);
    debug "get_gitolite_conf $output";
    my $fh = new FileHandle "<$gitolite_conf" or die "Can't read $gitolite_conf: $!";
    my @sshkeys = File::Find::Rule->file()->in( "$gitolite_admin/keydir" );
    foreach my $keyfile (@sshkeys) {
        next if $keyfile =~ m/gitolite_admin.pub/;
        $config->{sshkeys}{ basename($keyfile) } = read_file($keyfile);
        my $user = basename($keyfile);
        $user =~ s/\.pub//;
        $config->{users}{ $user } = basename($keyfile);
    }
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/#.*$//;
        if ($line =~ m/^\@(\w+)\s*=\s*(.*)$/) {
            my $group = $1;
            my @users = split(/\s+/, $2);
            $config->{groups}{ $group } = [ @users ];
        }
        if ($line =~ m/^repo/) {
            next if $line =~ m/repo gitolite-admin$/;
            next if $line =~ m/repo testing$/;
            debug "Processing repo $line";
            my @repos = split(/\s+/, $line);
            shift @repos;
            my $rp =  Data::Dumper->Dump([\@repos], [qw/$repos/]);
            debug "repos $rp";
            $line = <$fh>;
            $line =~ s/#.*$//;
            while($line !~ m/^\s*$/) {
                my ($perms, $things) = split(/\s+=\s+/, $line);
                debug "\$perms = $perms, \$things = $things";
                $perms =~ s/^\s+//;
                my @things = split(/\s+/, $things);
                foreach my $repo (@repos) {
                    if ($repo =~ m!/!) {
                        my @bits = split("/", $repo);
                        $config->{repos}{$bits[0]}{$repo}=$bits[1];
                        $config->{projects}{$bits[0]}{$repo}=$bits[1];
                    }
                    foreach my $thing (@things) {
                        $config->{repos}{ $repo } {$perms}{$thing} = $thing;
                    }
                }
                $line = <$fh>;
                last unless defined $line;
                $line =~ s/#.*$//;
            }
        }
    }
    save_config();
    $output = Data::Dumper->Dump([$config], [qw/$config/]);
    debug "after get_gitolite_config $output";
}
sub parse_config {
}
sub read_file {
    my ($filename) = @_;
    debug "Reading $filename";
    my $fh = new FileHandle "<$filename" or die "Can't read $filename: $!";
    my @lines = <$fh>;
    chomp(@lines);
    $fh->close;
    my $contents =  join("\n", @lines);
    debug "contents $contents";
    return $contents;
}
sub Exists {
    my ($hash, $key) = @_;
    return undef unless defined $hash;
    my %copy = %{ $hash };
    return exists $copy{ $key };
}
sub save_config {
    debug "saving to $gitoweb_cfg";
    my $output = Data::Dumper->Dump([$config], [qw/$config/]);
    debug "$output";
    my $fh = new FileHandle ">$gitoweb_cfg";
    $fh->print( $output );
    $fh->close;
}
sub load_config {
    my $output = Data::Dumper->Dump([$config, $gitoweb_cfg ], [qw/$config $gitoweb_cfg/]);
    debug "before load $output";

    do $gitoweb_cfg;
    $output = Data::Dumper->Dump([$config], [qw/$config/]);
    debug "after load $output";
}
sub get_repo_details {
    my ($project, $repo) = @_;
    chdir "${repodir}/${project}/${repo}.git";
    my $fh = new FileHandle("$gitpath ls-tree -r HEAD|") or die "Can't run  git: $!";
    while (my $line = <$fh>) {
        debug $line;
        my ($mode, $type, $object, $file) = split(/\s+/, $line);
        my $output = Data::Dumper->Dump([$mode, $type, $object, $file ], [qw/$mode $type $object $file/]);
        debug $output;
        $config->{repos}{$repo}{files}{$file} = { mode => $mode,
                                                  object => $object,
                                                  contents => get_file_contents($project, $repo, $file),
                                              };
    }
    $fh->close;
}
sub get_file_contents {
    my ($project, $repo, $file) = @_;
    my $object = $config->{repos}{$repo}{files}{$file}{object};
    my $output = Data::Dumper->Dump([$project, $repo, $file, $object ], [qw/$project $repo $file $object/]);
    debug $output;
    chdir "${repodir}/${project}/${repo}.git";
    my @contents = ();
    debug "$gitpath cat-file $object";
#    my $fh = new FileHandle("$gitpath cat-file $object |") or die "Can't run  git: $!";
#    while (my $line = <$fh>) {
#        push(@contents, $line);
#    }
#    $fh->close;
    return join("\n", @contents);
}
true;
