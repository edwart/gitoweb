package GitWeb;
use FindBin qw/  $Bin /;
use File::Basename qw/ dirname /;
use feature 'say';
use File::HomeDir;
use Dancer2;
use Crypt::PBKDF2;
use Dancer2::Plugin::Database;
use Git;
use Template;
use Sys::Hostname;
use Data::Dumper::Hash;
my $login = getlogin || getpwuid($<);
my $hostname = hostname;

our $VERSION = '0.1';

my $salt = 'somethingfisshy';
my $pbkdf2 = Crypt::PBKDF2->new(
	hash_class => 'HMACSHA2',
	hash_args => {
		sha_size => 512,
	},
    iterations => 10000,
    salt_len => 10,
);
my $gitpath = config->{'gitpath'};
my $repodir = config->{'repodir'};
my $home = File::HomeDir->my_home;
my $gitolite_admin = "$home/gitolite-admin";
my $gitolite_conf = "$home/gitolite-admin/conf/gitolite.conf";
set session_dir => dirname($Bin).'/sessions';


=for 
hook before => sub {
	unless (-d $gitolite_admin ) {
		initial_setup();
	}
	if (!session('user') && request->dispatch_path !~ m{^/(login|register)}) {
		# Pass the original path requested along to the handler:
		forward '/login', { requested_path => request->dispatch_path };
	}
};
=cut

get '/' => sub {
#	reconfig_gitolite();
    my @repos = database->quick_select('repos', {});
    template 'index', { repos => \@repos };
};

get '/reset' => sub {
	reset_it();
	redirect '/';
};

get '/setup' => sub {
	initial_setup();
	forward '/';
};
get '/users' => sub {
    my @users = database->quick_select('user', {});
    template 'useradmin', { users => \@users };
};
get '/login' => sub {
    template 'login', { path => vars->{requested_path} };
};
post '/login' => sub {
    chomp params->{pass};
    my $hash = $pbkdf2->generate( params->{pass}, $salt );
    my $rows = database->quick_count('user', { name => params->{user}, pass => $hash });
	debug Dump(rows => $rows);
    unless ($rows == 1) {
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
    my $rows = database->quick_count('user', { name => params->{user} });
	debug Dump(rows => $rows);
	debug "insert ".params->{user};
    database->quick_insert('user', { name => params->{user} ,
                                     pass => $pbkdf2->generate( params->{pass}, $salt ) });

    session user => params->{user};
    redirect '/';
};

any '/logout' => sub {
    session->delete(session('user'));
    template 'login';
    redirect '/login';
};
get '/project/:project' => sub {
    my $project = database->quick_select('project', {name => params->{project}});
    my @repos = database->quick_select('repository', {name => params->{project}});
	template 'project', { repos => \@repos, project => $project };
};

get '/projects' => sub {
    my @projects = database->quick_select('project', {});
	debug Dump(projects => \@projects);
	template 'projects', { projects => \@projects, error => params->{error} };
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
    my $rows = database->quick_count('project', { name => params->{name} });
    unless ($rows == 0) {
        redirect '/newproject?error=Project already exists';
    }
    debug "making project in ".params->{name};
    database->quick_insert('project', { name => params->{'name'},
                                     description => params->{'desc'} } );
    redirect '/';

};
get '/newrepo' => sub {
    my @projects = database->quick_select('project', {});
    template 'newrepo', {  projects => \@projects, error => params->{'error'}  };
};
get '/newrepo/:project' => sub {
    my @projects = database->quick_select('project', {});
    my $project = database->quick_select('project', {name => params->{project}});
    template 'newrepo', {  projects => \@projects, currentproject => params->{project}, error => params->{'error'}  };
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
    my $rows = database->quick_count('repository', { name => params->{'name'} });
    unless ($rows == 0) {
        redirect '/newproject?error="Repository already exists"';
    }
	my $project = database->quick_select('project', {name => params->{project}});
	debug Dump(project=> $project);

    database->quick_insert('repository', { name => params->{'name'},
                                     description => params->{'desc'},
									 projectid => $project->{id},
							 		 is_public => params->{public} eq 'on'});

	reconfig_gitolite();
	redirect '/';

};
get '/repo/*/*' => sub {
    my ($project,$repo) = splat;
	my $git = Git->repository(Directory =>  "$repodir/$project/${repo}.git" );

	my @files = $git->command('log', '--pretty=format:',  '--name-only',  '--diff-filter=A');
	debug Dump(files => \@files);

	template 'repo', { user => $login, hostname => $hostname, repo => $repo , project => $project, files => \@files};
};
get '/sshkeys' => sub {
	my @sshkeys = database->quick_select('sshkeys', {});
	template 'sshkeys', { sshkeys => \@sshkeys };
};
get '/addsshkey' => sub {
	template 'addsshkey';
};
post '/addsshkey' => sub {
	my %params = params;
	debug Dump(params=> \%params);
	my $count = database->quick_count('sshkeys', { name => params->{'keyname'} });
	debug Dump(count => $count);
	if ($count < 1) {
		database->quick_insert('sshkeys', { name => params->{'keyname'},
											sshkey => params->{'sshkey'},
										  }
							  );
		my $gitolite_keydir = "$home/gitolite-admin/keydir";
		my $keyfile = join("/",$gitolite_keydir, params->{'keyname'}.".pub");
		my $fh;
		chdir("$home/gitolite-admin");

		$fh = new FileHandle ">$keyfile" or error "can't write $keyfile: $!";
		$fh->print(params->{'sshkey'});
		$fh->close;
		system("git add keydir");
		system(qq!git commit -m "added $keyfile"!);
		reconfig_gitolite();
	}
	redirect '/sshkeys';
};
sub reconfig_gitolite {
	my @sshkeys = database->quick_select('sshkeys', {});
	debug Dump(sshkeys => \@sshkeys);
	my @repos = database->quick_select('repos', {});
	my @users = database->quick_select('user', {});
	my @usernames = map { $_->{name} } @sshkeys;
	my @groups = database->quick_select('groups', {});
	my @group_members = database->quick_select('group_members', {});

	my @changes = ();
	my %groups = map { $_->{name} => {} } @groups;
	my $processed = template 'gitolite.conf', { users => \@users, usernames => \@usernames, groups => \@groups, repos => \@repos }, {layout => 0 };
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
	foreach my $what (qw!bin gitolite-admin repositories projects.list git2 git2.pub .gitolite* .ssh sessions!) {
		debug "rm -rf $home/$what";
		my $fh = new FileHandle "rm -rf $home/$what 2>&1|";
		while (my $line = <$fh>) {
			debug $line;
		}
	}
	chdir ("$home/gitoweb");
	my $fh = new FileHandle "sqlite3 gitweb.sqlite < database.sql|";
	while (my $line = <$fh>) {
		debug $line;
	}
	debug "reset";
}
sub initial_setup {
	unless (-d $gitolite_admin ) {
		say(qq!ssh-keygen -b 2048 -t rsa -f $home/.ssh/id_rsa -P "" -q!);
		system(qq!ssh-keygen -b 2048 -t rsa -f $home/.ssh/id_rsa -P "" -q!);
		my $fh = new FileHandle "> $home/.ssh/config";
		$fh->print("Host *\n\tStrictHostKeyChecking no\n");
		$fh->close;
	}
	unless (-d  "$home/bin") {
		mkdir("$home/bin");
		say(qq!$home/gitolite/install -to $home/bin!);
		system(qq!$home/gitolite/install -to $home/bin!);
		say(qq!$home/bin/gitolite setup -pk  $home/.ssh/id_rsa.pub!);
		system(qq!$home/bin/gitolite setup -pk  $home/.ssh/id_rsa.pub!);
		chdir $home;
		system(qq!git clone ${repodir}/gitolite-admin.git!);
	}
}
true;
