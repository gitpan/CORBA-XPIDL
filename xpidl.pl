#!/usr/bin/perl -w

use strict;
use Getopt::Std;
use Pod::Usage;
use File::Temp qw(tempfile);

use CORBA::IDL::parserxp;
use CORBA::IDL::symbtab;
use CORBA::XPIDL::check;

my %handlers = (
	header		=> \&handler_header,
	typelib		=> \&handler_typelib,
	doc			=> \&handler_doc,
	java		=> \&handler_java,
	html		=> \&handler_html,
);

my %opts;
getopts('ae:i:I:m:o:t:vwx', \%opts)
		or pod2usage(-verbose => 1);

if ($opts{v}) {
	print "CORBA::XPIDL $CORBA::XPIDL::check::VERSION\n";
	print "CORBA::IDL $CORBA::IDL::node::VERSION\n";
	print "based on IDL $Parser::IDL_version\n";
	print "$0\n";
	print "Perl $] on $^O\n";
	exit;
}

my $filename = shift @ARGV;
pod2usage(-message => "no input file", -verbose => 1)
		unless (defined $filename);
pod2usage(-message => "extra arguments after input file", -verbose => 1)
		if (@ARGV);
pod2usage(-message => "must specify output mode", -verbose => 1)
		unless ($opts{m});
pod2usage(-message => "unknown mode $opts{m}", -verbose => 1)
		unless (exists $handlers{$opts{m}});
$opts{t} = "1.2" unless (exists $opts{t});
die "version $opts{t} not supported.\n"
		if ($opts{t} eq "1.0");
die "version $opts{t} not recognised.\n"
		if ($opts{t} ne "1.1" and $opts{t} ne "1.2");

my $parser = new Parser;
#$parser->YYData->{collision_allowed} = 1;
$parser->YYData->{verbose_error} = 1;			# 0, 1
$parser->YYData->{verbose_warning} = $opts{w};	# 0, 1
$parser->YYData->{verbose_info} = $opts{w};		# 0, 1
$parser->YYData->{verbose_deprecated} = 1;		# 0, 1 (concerns only version '2.4' and upper)
$parser->YYData->{opt_i} = $opts{i} if (exists $opts{i});
if ($opts{m} ne "html") {
	$parser->YYData->{opt_a} = $opts{a};
	$parser->YYData->{opt_e} = $opts{e};
	$parser->YYData->{opt_m} = $opts{m};
	$parser->YYData->{opt_o} = $opts{o};
	$parser->YYData->{opt_t} = $opts{t};
}
$parser->YYData->{symbtab} = new CORBA::IDL::Symbtab($parser);
my $base_includes = [];
my @built_in = ();

if ($opts{x}) {
	@built_in = built_in($parser);
	# no preprocess for #include
	$parser->YYData->{filename} = $filename;
	$parser->YYData->{lineno} = 1;
	$parser->Run($filename);
} else {
	my $tmp = tempfile();
	$base_includes = preprocess::process($tmp, $filename, $opts{I});
	$parser->Run($tmp, $filename);
}

$parser->YYData->{symbtab}->CheckForward();
$parser->YYData->{symbtab}->CheckRepositoryID();

if (        exists $parser->YYData->{root}
		and ! exists $parser->YYData->{nb_error} ) {
	$parser->YYData->{root}->visit(new CORBA::XPIDL::checkVisitor($parser, $opts{t}, $opts{m}));
}
if (exists $parser->YYData->{nb_error}) {
	my $nb = $parser->YYData->{nb_error};
	print "$nb error(s).\n"
}
if (        $parser->YYData->{verbose_warning}
		and exists $parser->YYData->{nb_warning} ) {
	my $nb = $parser->YYData->{nb_warning};
	print "$nb warning(s).\n"
}
if (        $parser->YYData->{verbose_info}
		and exists $parser->YYData->{nb_info} ) {
	my $nb = $parser->YYData->{nb_info};
	print "$nb info(s).\n"
}
if (        $parser->YYData->{verbose_deprecated}
		and exists $parser->YYData->{nb_deprecated} ) {
	my $nb = $parser->YYData->{nb_deprecated};
	print "$nb deprecated(s).\n"
}

if (        exists $parser->YYData->{root}
		and ! exists $parser->YYData->{nb_error} ) {
	if ($opts{x}) {
		$parser->YYData->{symbtab}->Export();
	}
	$handlers{$opts{m}}($parser, \%opts);
}

sub handler_header {
	my ($parser) = @_;
	use CORBA::XPIDL::header;
	$parser->YYData->{root}->visit(new CORBA::XPIDL::nameVisitor($parser));
	$parser->YYData->{root}->visit(new CORBA::XPIDL::headerVisitor($parser, $base_includes));
}

sub handler_typelib {
	my ($parser, $opts) = @_;
	use CORBA::XPIDL::xpt;
	$parser->YYData->{root}->visit(new CORBA::XPIDL::xptVisitor($parser));
}

sub handler_doc {
	my ($parser) = @_;
	use CORBA::XPIDL::header;	# for nameVisitor
	use CORBA::XPIDL::doc;
	$parser->YYData->{root}->visit(new CORBA::XPIDL::nameVisitor($parser));
	$parser->YYData->{root}->visit(new CORBA::XPIDL::docVisitor($parser));
}

sub handler_html {
	my ($parser) = @_;
	use Data::Dumper;
	use CORBA::HTML::index;
	use CORBA::HTML::html;

	use vars qw ($global);
	unless (do "index.lst") {
		$global->{index_module} = {};
		$global->{index_interface} = {};
		$global->{index_value} = {};
		$global->{index_entry} = {};
	}

	$parser->YYData->{opt_s} = "style";
	push @{$parser->YYData->{root}->{list_decl}}, @built_in;
	$parser->YYData->{root}->visit(new CORBA::HTML::indexVisitor($parser));
	$parser->YYData->{root}->visit(new CORBA::HTML::htmlVisitor($parser));

	if (open PERSISTANCE,"> index.lst") {
		print PERSISTANCE Data::Dumper->Dump([$global], [qw(global)]);
		close PERSISTANCE;
	} else {
		warn "can't open index.lst.\n";
	}
}

sub handler_java {
	my ($parser) = @_;
	use CORBA::XPIDL::java;
	$parser->YYData->{root}->visit(new CORBA::XPIDL::javaVisitor($parser));
}

sub built_in {
	my ($parser) = @_;
	$parser->YYData->{filename} = "built-in";
	$parser->YYData->{lineno} = 0;
	$parser->YYData->{doc} = '';
	my @list_decl = ();
	# from nsrootidl.idl
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new BooleanType($parser, 'value' =>'boolean'),
			idf			=>	'PRBool'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new OctetType($parser, 'value' =>'octet'),
			idf			=>	'PRUint8'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned short'),
			idf			=>	'PRUint16'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned short'),
			idf			=>	'PRUnichar'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned long'),
			idf			=>	'PRUint32'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned long long'),
			idf			=>	'PRUint64'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned long long'),
			idf			=>	'PRTime'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'short'),
			idf			=>	'PRInt16'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'long'),
			idf			=>	'PRInt32'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'long long'),
			idf			=>	'PRInt64'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned long'),
			idf			=>	'nsrefcnt'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned long'),
			idf			=>	'nsresult'
	);
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned long'),
			idf			=>	'size_t'
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef },
			'idf'		=>	'voidPtr',
			'native'	=>	'void',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef },
			'idf'		=>	'charPtr',
			'native'	=>	'char',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef },
			'idf'		=>	'unicharPtr',
			'native'	=>	'PRUnichar',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'nsid' => undef },
			'idf'		=>	'nsIDRef',
			'native'	=>	'nsID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'nsid' => undef },
			'idf'		=>	'nsIIDRef',
			'native'	=>	'nsIID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'nsid' => undef },
			'idf'		=>	'nsCIDRef',
			'native'	=>	'nsCID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef, 'nsid' => undef },
			'idf'		=>	'nsIDPtr',
			'native'	=>	'nsID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef, 'nsid' => undef },
			'idf'		=>	'nsIIDPtr',
			'native'	=>	'nsIID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef, 'nsid' => undef },
			'idf'		=>	'nsCIDPtr',
			'native'	=>	'nsCID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'nsid' => undef },
			'idf'		=>	'nsID',
			'native'	=>	'nsID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'nsid' => undef },
			'idf'		=>	'nsIID',
			'native'	=>	'nsIID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'nsid' => undef },
			'idf'		=>	'nsCID',
			'native'	=>	'nsCID',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef },
			'idf'		=>	'nsQIResult',
			'native'	=>	'void',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'domstring' => undef },
			'idf'		=>	'DOMString',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'domstring' => undef },
			'idf'		=>	'DOMStringRef',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef, 'domstring' => undef },
			'idf'		=>	'DOMStringPtr',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'utf8string' => undef },
			'idf'		=>	'AUTF8String',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'utf8string' => undef },
			'idf'		=>	'AUTF8StringRef',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef, 'utf8string' => undef },
			'idf'		=>	'AUTF8StringPtr',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'cstring' => undef },
			'idf'		=>	'ACString',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'cstring' => undef },
			'idf'		=>	'ACStringRef',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef, 'cstring' => undef },
			'idf'		=>	'ACStringPtr',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'astring' => undef },
			'idf'		=>	'AString',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ref' => undef, 'astring' => undef },
			'idf'		=>	'AStringRef',
			'native'	=>	'ignored',
	);
	push @list_decl, new NativeType($parser,
			'props'		=>	{ 'ptr' => undef, 'astring' => undef },
			'idf'		=>	'AStringPtr',
			'native'	=>	'ignored',
	);
	# from domstubs.idl
	push @list_decl, new TypeDeclarator($parser,
			type		=>	new IntegerType($parser, 'value' =>'unsigned long long'),
			idf			=>	'DOMTimeStamp'
	);
		# Core
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMAttr');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCDATASection');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCharacterData');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMComment');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMDOMImplementation');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMDocument');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMDocumentFragment');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMDocumentType');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMElement');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMEntity');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMEntityReference');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMNSDocument');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMNamedNodeMap');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMNode');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMNodeList');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMNotation');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMProcessingInstruction');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMText');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMDOMStringList');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMNameList');
		# Needed for raises() in our IDL
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'DOMException');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'RangeException');
		# Style Sheets
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMStyleSheetList');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMLinkStyle');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMStyleSheet');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMMediaList');
		# Views
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMAbstractView');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMDocumentView');
		# Base
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMWindow');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMWindowInternal');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMWindowCollection');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMPlugin');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMPluginArray');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMMimeType');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMMimeTypeArray');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMBarProp');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMNavigator');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMScreen');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMHistory');
		# Events
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMEvent');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMEventTarget');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMEventListener');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMEventGroup');
		# HTML
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMHTMLElement');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMHTMLFormElement');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMHTMLCollection');
		# CSS
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSValue');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSValueList');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSPrimitiveValue');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSRule');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSRuleList');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSStyleSheet');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSStyleDeclaration');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCounter');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMRect');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMRGBColor');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSStyleRule');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCSSStyleRuleCollection');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMHTMLTableCaptionElement');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMHTMLTableSectionElement');
		# Range
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMRange');
		# Crypto
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCRMFObject');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMCrypto');
	push @list_decl, new ForwardRegularInterface($parser, 'idf' => 'nsIDOMPkcs11');
	return @list_decl;
}

package preprocess;

use Carp;
use IO::File;

my $line;
my %files;
my @incpath;
my @base_includes;

sub process {
	my ($out, $filename, $incpath) = @_;
	@incpath = split /;/, $incpath if (defined $incpath);
	@base_includes = ();
	parse_file($out, $filename);
	seek $out, 0, 0;
	return \@base_includes;
}

sub find_file {
	my ($filename) = @_;
	if ($filename !~ /^\//) {
		return $filename if (-e $filename);
		foreach (@incpath) {
			my $path = $_ . "/" . $filename;
			return $path if (-e $path);
		}
	}
	return $filename;
}

sub add_file {
	my ($filename, $recursive) = @_;
	push @base_includes, $filename unless ($recursive);
}

sub parse_file {
	my ($out, $filename, $recursive) = @_;

	return if (exists $files{$filename});
	$files{$filename} = 1;
	my $fh;
	$filename = find_file($filename) if ($recursive);
	open $fh, $filename
			or warn("can't open $filename ($!)\n"),
			   return;
	print($out "# 1 \"$filename\"\n");
	my $lineno = 1;

	while (1) {
		    $line
		or  $line = <$fh>,
		or  last;

		for ($line) {
			s/^(\n)//
					and print($out $1),
					    $lineno ++,
					    last;
			s/^(%{)//
					and print($out $1),
					    parse_code($out, $fh, \$lineno),
						last;
			s/^(\/\*)//
					and print($out $1),
					    parse_comment($out, $fh, \$lineno),
						last;
			s/^\s*#\s*include\s*\"([0-9A-Za-z_.\/-]+)\".*\n//
					and add_file($1, $recursive),
					    parse_file($out, $1, 1),
					    $lineno ++,
					    print($out "# $lineno \"$filename\"\n"),
					    last;
			s/^(.)//
					and print($out $1);
		}
	}
	close $fh;
}

sub parse_code {
	my ($out, $fh, $lineno) = @_;

	while (1) {
		    $line
		or  $line = <$fh>,
		or  last;

		for ($line) {
			s/^(\n)//
					and print($out $1),
					    $$lineno ++,
					    last;
			s/^(%})//
					and print($out $1),
					    return;
			s/^(\/\*)//
					and print($out $1),
					    parse_comment($out, $fh, $lineno),
						last;
			s/^(.)//
					and print($out $1);
		}
	}
}

sub parse_comment {
	my ($out, $fh, $lineno) = @_;

	while (1) {
		    $line
		or  $line = <$fh>,
		or  last;

		for ($line) {
			s/^(\n)//
					and print($out $1),
					    $$lineno ++,
					    last;
			s/^(\*\/)//
					and print($out $1),
					    return;
			s/^(.)//
					and print($out $1),
		}
	}
}

__END__

=head1 NAME

xpidl - XPIDL parser

=head1 SYNOPSIS

xpidl -m I<mode> [-a] [-w] [-v] [-t I<version number>] [-I I<path>] [-o I<basename> | -e I<filename.ext>] I<filename>.idl

=head1 OPTIONS

=over 8

=item B<-a>

Emit annotations to typelib.

=item B<-w>

Turn on warnings (recommended).

=item B<-v>

Display version.

=item B<-t> I<version number>

Create a typelib of a specific version number.

=item B<-I> I<path>

Add entry to start of include path for ``#include "nsIThing.idl"''.

=item B<-o> I<basename>

Use basename (e.g. ``/tmp/nsIThing'') for output.

=item B<-e> I<filename.ext>

Use explicit output filename.

=item B<-i> I<path>

Specify a path for import (only for IDL version 3.0).

=item B<-x>

Enable export (only for IDL version 3.0).

=item B<-m> I<mode>

Specify output mode:

=over 4

=item header    Generate C++ header                           (.h)

=item typelib   Generate XPConnect typelib                    (.xpt)

=item doc       Generate HTML documentation (compat xpidl)    (.html)

=item java      Generate Java interface                       (.java)

=item html      Generate HTML documentation (use idl2html)    (.html)

=back

=back

=head1 DESCRIPTION

B<xpidl> parses the given input file (IDL) and generates
a ASCII file with the .ast extension.

B<xpidl> is a Perl OO application what uses the visitor design pattern.
The parser is generated by Parse::Yapp.

CORBA Specifications, including IDL (Interface Definition Language)
 are available on E<lt>http://www.omg.org/E<gt>.

XPCOM Type Library File Format, version 1.1, is available on
http://mozilla.org/scriptable/typelib_file.html

=head1 SEE ALSO

L<CORBA::IDL>, L<xpt_dump.pl>, L<xpt_link.pl>

=head1 AUTHORS

The original version (C language) is mozilla.org code.

Port to Perl by Francois Perrad, francois.perrad@gadz.org

=head1 COPYRIGHT

Copyright 2004, Francois Perrad.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

