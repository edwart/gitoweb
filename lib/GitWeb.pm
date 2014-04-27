package GitWeb;
use Dancer2;
use Crypt::PBKDF2;
use Dancer2::Plugin::Database;

our $VERSION = '0.1';
my $dbh = database('gitweb.sqlite');
my $pbkdf2 = Crypt::PBKDF2->new(
	hash_class => 'HMACSHA2',
	hash_args => {
		sha_size => 512,
	},
    iterations => 10000,
    salt_len => 10,
);
get '/' => sub {
    check_logged_in();
    template 'index';
};

get '/login' => sub {
    template 'login', { path => vars->{requested_path} };
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
                                     pass => $pbkdf2->generate( params->{pass} ) });



    template 'register';
};

post '/login' => sub {
    my $rows = database->quick_count('user', { user => params->{user}, pass => $pbkdf2->generate( params->{pass} ) });
    unless ($rows == 1) {
        redirect '/login?failed=1';
    }
    else {
        session user => params->{user};
        redirect params->{requested_path} || '/';
    }
};
any '/logout' => sub {

    session->delete(session('user'));
    template 'login';
    redirect '/login';
};
sub check_logged_in {
  if (! session('user') && request->path_info !~ m{^/login}) {
        var requested_path => request->path_info;
        redirect '/login';
    }

}

true;
