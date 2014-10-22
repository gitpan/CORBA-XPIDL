#!/usr/bin/perl -w

use strict;

use Getopt::Std;
use Pod::Usage;
use CORBA::XPIDL::xpt;

my %opts;
getopts('v', \%opts)
		or pod2usage(-exitval => 1, -verbose=> 1);

my $filename = shift;

pod2usage(-exitval => 1, -verbose=> 1)
		if (!defined $filename or @ARGV);

eval {
	open IN, $filename
			or die "FAILED: can't read $filename\n";
	binmode IN, ":raw";
	undef $/;
	my $rv = <IN>;
	close IN;

	$XPT::demarshal_not_abort = 1;
	$XPT::demarshal_retcode = 0;
	my $offset = 0;
	my $file = XPT::File::demarshal(\$rv, \$offset);
	print "WARNING: problem(s) occured during parsing.\n\n"
			if ($XPT::demarshal_retcode);

	$XPT::stringify_verbose = 1 if ($opts{v});
	print $file->stringify();
	exit($XPT::demarshal_retcode);
};
if ($@) {
	warn $@;
	exit(1);
}

###############################################################################

__END__

=head1 NAME

xpt_dump - typelib dumper

=head1 SYNOPSIS

C<xpt_dump> [-v] F<filename.xpt>

=head1 OPTIONS

=over 8

=item -v

verbose mode

=back

=head1 DESCRIPTION

C<xpt_dump> is a utility for dumping the contents of a typelib file (.xpt)

=head1 MORE INFORMATION

XPCOM Type Library File Format, version 1.1, is available on
http://mozilla.org/scriptable/typelib_file.html

=head1 SEE ALSO

L<xpidl.pl>, L<xpt_link.pl>

=head1 AUTHORS

The original version (C language) is mozilla.org code.

Port to Perl by Francois Perrad, francois.perrad@gadz.org

=head1 COPYRIGHT

Copyright 2004, Francois Perrad.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
