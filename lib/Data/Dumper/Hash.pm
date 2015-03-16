package Data::Dumper::Hash;
use strict;
use warnings;
use Tie::IxHash;
require Exporter;
use vars qw/@ISA @EXPORT @EXPORT_OK/;
@ISA = qw/Exporter/;
@EXPORT = qw/Dump/;
@EXPORT_OK = qw/Dump/;


use Data::Dumper;

sub Dump {
	tie (my %hash, 'Tie::IxHash');
	%hash = @_;
	my @vals = ();
	my @names = ();

	while ( my ($key, $val) = each %hash) {
		push(@vals, $val);
		push(@names, $key);
	}
	return Data::Dumper->Dump(\@vals, \@names);
}
1;
__END__

=head1 NAME

Data::Dumper::Hash

=head1 DESCRIPTION

This is a simple utility module to make dumping data structures easier.
The standard Data::Dumper module has a awkward interface when you want to have sensible names output rather than the default VAR1, VAR2 etc

This module exports a single subroutine to which you pass a hash - the keys being the names of the variables and the values being the actual value to be dumped
so you use it like this

 print Dump(variable => <value>);


=head1 Return value

The dumped data structure

=head1 AUTHOR

Tony Edwardson <tedwardson.extranet.soufflet-group.com>

=head1 LICENSE AND COPYRIGHT

 (c) 2014 Grouppe Soufflet
 All Original Content (c) 2014 Grouppe Soufflet
 Site Contents/Photography (c) 2014 Grouppe Soufflet
 All Original Content (c) 2014 Grouppe Soufflet, All Rights Reserved

=cut
