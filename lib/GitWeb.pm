package GitWeb;
use Dancer2;
use Crypt::PBKDF2;
use Dancer2::Plugin::Database;
use Data::Dumper;

our $VERSION = '0.1';
my $dbh = database('gitweb.sqlite');
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


get '/' => sub {
    check_logged_in();
    template 'index';
};

get '/login' => sub {
    template 'login', { path => vars->{requested_path} };
};
post '/login' => sub {
    chomp params->{pass};
    my $hash = $pbkdf2->generate( params->{pass}, $salt );
    my $rows = database->quick_count('user', { user => params->{user}, pass => $hash });
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
    unless (params->{user} and params->{pass}) {
        redirect '/register';
    }
    my $rows = database->quick_count('user', { user => params->{user} });
    unless ($rows == 0) {
        redirect '/register';
    }
    database->quick_insert('user', { user => params->{user} ,
                                     pass => $pbkdf2->generate( params->{pass}, $salt ) });

    session user => params->{user};
    redirect '/';
};

any '/logout' => sub {
    session->delete(session('user'));
    template 'login';
    redirect '/login';
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
    database->quick_insert('project', { name => params->{'name'},
                                     description => params->{'desc'} } );
    redirect '/project/';

};
get '/newrepo' => sub {
     my @projects = database->quick_select('project', {});
     debug Dumper \@projects;
    
     template 'newrepo', { currentproject => params->{'project'}, projects =>\@projects, error => params->{'error'}  };
};
post '/newrepo' => sub {
    unless (params->{project}) {
        redirect "/newrepo?error=Mandatory param Project not supplied";
    }
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
    database->quick_insert('repository', { name => params->{'name'},
                                     description => params->{'desc'} } );

    
    my $dir = join('/', $repodir, params->{'project'});
    mkdir $dir unless -d $dir;
    $dir .= '/'.params->{'name'};
    mkdir $dir unless -d $dir;
    chdir $dir;
    debug "making repo in $dir";
    system($gitpath, '--bare', 'init');
    redirect '/repo/'. params->{'name'}.'/empty';
};
get '/repo/*/*' => sub {
    my ($repo, $status) = splat;
    debug "repo  = $repo";
    debug "status  = $status";
    if ($status eq 'empty') {
        template 'emptyrepo', { repo => $repo };
    }
    else {
        template 'repo', { repo => $repo };
    }
};

sub check_logged_in {
  if (! session('user') && request->path_info !~ m{^/login}) {
        var requested_path => request->path_info;
        redirect '/login';
    }

}

true;
