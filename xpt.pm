use strict;
use UNIVERSAL;

package XPT;

use Carp;

our $demarshal_retcode;
our $demarshal_not_abort;
our $stringify_verbose;
our $data_pool_offset;
our $data_pool;
our $param_problems;

use constant int8								=> 0;
use constant int16								=> 1;
use constant int32								=> 2;
use constant int64								=> 3;
use constant uint8								=> 4;
use constant uint16								=> 5;
use constant uint32								=> 6;
use constant uint64								=> 7;
use constant float								=> 8;
use constant double								=> 9;
use constant boolean							=> 10;
use constant char								=> 11;
use constant wchar_t							=> 12;
use constant void								=> 13;
use constant nsIID								=> 14;
use constant domstring							=> 15;
use constant pstring							=> 16;
use constant pwstring							=> 17;
use constant InterfaceTypeDescriptor			=> 18;
use constant InterfaceIsTypeDescriptor			=> 19;
use constant ArrayTypeDescriptor				=> 20;
use constant StringWithSizeTypeDescriptor		=> 21;
use constant WideStringWithSizeTypeDescriptor	=> 22;
use constant utf8string							=> 23;
use constant cstring							=> 24;
use constant astring							=> 25;


sub ReadBuffer {
	my ($r_buffer, $r_offset, $n) = @_;
	my $str = substr $$r_buffer, $$r_offset, $n;
	croak "not enough data.\n"
			if (length($str) != $n);
	$$r_offset += $n;
	return $str;
}

sub Read8 {
	my ($r_buffer, $r_offset) = @_;
	my $str = ReadBuffer($r_buffer, $r_offset, 1);
	return unpack "C", $str;
}

sub Write8 {
	my ($value) = @_;
	return pack "C", $value;
}

sub Read16 {
	my ($r_buffer, $r_offset) = @_;
	my $str = ReadBuffer($r_buffer, $r_offset, 2);
	return unpack "n", $str;
}

sub Write16 {
	my ($value) = @_;
	return pack "n", $value;
}

sub Read32 {
	my ($r_buffer, $r_offset) = @_;
	my $str = ReadBuffer($r_buffer, $r_offset, 4);
	return unpack "N", $str;
}

sub Write32 {
	my ($value) = @_;
	return pack "N", $value;
}

sub Read64 {
	my ($r_buffer, $r_offset) = @_;
	my $str = ReadBuffer($r_buffer, $r_offset, 8);
	# unsupported
	return 0;
}

sub Write64 {
	my ($value) = @_;
	return "\0\0\0\0\0\0\0\0";
}

sub ReadStringInline {
	my ($r_buffer, $r_offset) = @_;
	my $len = Read16($r_buffer, $r_offset);
	my $str = ReadBuffer($r_buffer, $r_offset, $len);
	return $str;
}

sub WriteStringInline {
	my ($value) = @_;
	return Write16(length($value)) . $value;
}

sub ReadCString {
	my ($r_buffer, $r_offset) = @_;
	my $offset = Read32($r_buffer, $r_offset);
	return "" unless ($offset);
	my $start = $data_pool_offset + $offset - 1;
	my $end = index $$r_buffer, "\0", $start;
	my $str = substr $$r_buffer, $start, $end - $start;
	return $str;
}

sub WriteCString {
	my ($value) = @_;
	return Write32(0) unless ($value);
	my $offset = 1 + length($data_pool);
	$data_pool .= $value . "\0";
	return Write32($offset);
}

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my %attr = @_;
	my $self = \%attr;
	bless($self, $class);
	return $self
}

##############################################################################

package XPT::File;

use base qw(XPT);

use Carp;

use constant MAGIC		=> "XPCOM\nTypeLib\r\n\032";

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $magic = XPT::ReadBuffer($r_buffer, $r_offset, length(MAGIC));
	die "libxpt: bad magic header in input file; found '",$magic,"', expected '",MAGIC,"'\n"
			unless ($magic eq MAGIC);

	my $major_version = XPT::Read8($r_buffer, $r_offset);
	my $minor_version = XPT::Read8($r_buffer, $r_offset);
	die "libxpt: newer version ",$major_version,".",$minor_version,"\n"
			unless ($major_version == 1);

	my $num_interfaces = XPT::Read16($r_buffer, $r_offset);
	my $file_length = XPT::Read32($r_buffer, $r_offset);

	die "libxpt: File length in header does not match actual length. File may be corrupt\n"
			if ($file_length != length $$r_buffer);

	my $interface_directory_offset = XPT::Read32($r_buffer, $r_offset);
	$XPT::data_pool_offset = XPT::Read32($r_buffer, $r_offset);

	my @annotations = ();
	my %interface_iid = ();
	my %interface_iid_nul = ();
	eval {
		my $annotation = XPT::Annotation::demarshal($r_buffer, $r_offset);
		push @annotations, $annotation;
		while (!$annotation->{is_last}) {
			$annotation = XPT::Annotation::demarshal($r_buffer, $r_offset);
			push @annotations, $annotation;
		}

		my $offset = $interface_directory_offset - 1;
		while ($num_interfaces --) {
			my $entry = XPT::InterfaceDirectoryEntry::demarshal($r_buffer, \$offset);
			if ($entry->{iid}->_is_nul()) {
				my $fullname = ($entry->{name_space} || "") . "::" . $entry->{name};
				$interface_iid_nul{$fullname} = $entry;
			} else {
				$interface_iid{$entry->{iid}->stringify()} = $entry;
			}
		}
	};
	if ($@) {
		$XPT::demarshal_retcode = 1;
		if ($XPT::demarshal_not_abort) {
			warn $@;
		} else {
			die $@;
		}
	}

	return new XPT::File(
			magic					=> $magic,
			major_version			=> $major_version,
			minor_version			=> $minor_version,
			interface_iid_nul		=> \%interface_iid_nul,
			interface_iid			=> \%interface_iid,
			annotations				=> \@annotations,
			file_length				=> $file_length,
			data_pool_offset		=> $XPT::data_pool_offset,
	)->_revolve();
}

sub _interface_directory {
	my $self = shift;
	my @list = ();
	foreach (sort keys %{$self->{interface_iid_nul}}) {
		my $entry = $self->{interface_iid_nul}->{$_};
		push @list, $entry;
	}
	foreach (sort keys %{$self->{interface_iid}}) {
		my $entry = $self->{interface_iid}->{$_};
		push @list, $entry;
	}
	return @list;
}

sub _revolve {
	my $self = shift;
	my @interface_directory = $self->_interface_directory();
	foreach my $itf (values %{$self->{interface_iid}}) {
		next unless (defined $itf->{interface_descriptor});		# ISupport
		my $desc = $itf->{interface_descriptor};
		my $idx_parent = $desc->{parent_interface_index};
		if ($idx_parent) {
			if ($idx_parent > scalar(@interface_directory)) {
				warn "parent_interface_index out of range! ($idx_parent)\n";
				$XPT::demarshal_retcode = 1;
			}
			$desc->{parent_interface} = $interface_directory[$idx_parent - 1];
		}
		foreach my $method (@{$desc->{method_descriptors}}) {
			foreach my $param (@{$method->{params}}) {
				my $type = $param->{type};
				if ($type->{tag} == XPT::InterfaceTypeDescriptor) {
					my $idx = $type->{interface_index};
					if ($idx > scalar(@interface_directory)) {
						warn "interface_index out of range! ($idx)\n";
						next;
					}
					$type->{interface} = $interface_directory[$idx - 1];
				}
			}
		}
	}
	return $self;
}

sub marshal {
	my $self = shift;

	my $header_size = length(MAGIC) + 1 + 1 + 2 + 4 + 4 + 4;
	my $annotations = "";
	foreach (@{$self->{annotations}}) {
		$annotations .= $_->marshal();
	}
#	while ( ($header_size + length($annotations)) % 4) {
#		$annotations .= "\0";
#	}
	$header_size += length($annotations);
	my $interface_directory_offset = $header_size + 1;
	my @interface_directory = $self->_interface_directory();
	$XPT::data_pool = "";
	my $interface_directory = "";
	foreach (@interface_directory) {
		$interface_directory .= $_->marshal();
	}

	my $data_pool_offset = $header_size + length($interface_directory);
	my $file_length = $header_size + length($interface_directory) + length($XPT::data_pool);
	my $buffer = $self->{magic};
	$buffer .= XPT::Write8($self->{major_version});
	$buffer .= XPT::Write8($self->{minor_version});
	$buffer .= XPT::Write16(scalar(@interface_directory));
	$buffer .= XPT::Write32($file_length);
	$buffer .= XPT::Write32($interface_directory_offset);
	$buffer .= XPT::Write32($data_pool_offset);
	$buffer .= $annotations;
	$buffer .= $interface_directory;
	$buffer .= $XPT::data_pool;
	return $buffer;
}

sub stringify {
	my $self = shift;
	my ($indent) = @_;
	$indent = "" unless (defined $indent);
	my $new_indent = $indent . "   ";
	my $more_indent = $new_indent . "   ";

	my @interface_directory = $self->_interface_directory();
	my $str = $indent . "Header:\n";
	if ($XPT::stringify_verbose) {
		$str .= $new_indent . "Magic beans:           ";
		foreach (split //, $self->{magic}) {
			$str .= sprintf("%02x", ord($_));
		}
		$str .= "\n";
		if ($self->{magic} eq MAGIC) {
			$str .= $new_indent . "                       PASSED\n";
		} else {
			$str .= $new_indent . "                       FAILED\n";
		}
	}
	$str .= $new_indent . "Major version:         " . $self->{major_version} . "\n";
	$str .= $new_indent . "Minor version:         " . $self->{minor_version} . "\n";
	$str .= $new_indent . "Number of interfaces:  " . scalar(@interface_directory) . "\n";
	if ($XPT::stringify_verbose) {
		$str .= $new_indent . "File length:           " . $self->{file_length} . "\n"
				if (exists $self->{file_length});
		$str .= $new_indent . "Data pool offset:      " . $self->{data_pool_offset} . "\n"
				if (exists $self->{data_pool_offset});
		$str .= "\n";
	}

	my $nb = -1;
	$str .= $new_indent . "Annotations:\n";
	foreach (@{$self->{annotations}}) {
		$nb ++;
		$str .= $more_indent . "Annotation #" . $nb;
		$str .= $_->stringify($new_indent);
	}
	if ($XPT::stringify_verbose) {
		$str .= $more_indent . "Annotation #" . $nb . " is the last annotation.\n";
	}

	$XPT::param_problems = 0;
	$nb = 0;
	$str .= "\n";
	$str .= $indent . "Interface Directory:\n";
	foreach my $entry (@interface_directory) {
		if ($XPT::stringify_verbose) {
			$str .= $new_indent . "Interface #" . $nb ++ . ":\n";
			$str .= $entry->stringify($new_indent . $new_indent, $self);
		} else {
			$str .= $entry->stringify($new_indent, $self);
		}
	}
	if ($XPT::param_problems) {
		$str .= "\nWARNING: ParamDescriptors are present with "
			 .  "bad in/out/retval flag information.\n"
			 .  "These have been marked with 'XXX'.\n"
			 .  "Remember, retval params should always be marked as out!\n";
	}

	return $str;
}

sub add_annotation {
	my $self = shift;
	my ($annotation) = @_;
	$annotation->{is_last} = 0;
	$self->{annotations} = [] unless (exists $self->{annotations});
	push @{$self->{annotations}}, $annotation;
}

sub terminate_annotations {
	my $self = shift;
	if (exists $self->{annotations}) {
		${$self->{annotations}}[-1]->{is_last} = 1;
	} else {
		my $annotation = new XPT::Annotation(
				is_last					=> 1,
				tag						=> 0,
		);
		$self->{annotations} = [ $annotation ];
	}
}

sub add_interface {
	my $self = shift;
	my ($entry) = @_;
	$self->{interface_iid_nul} = {} unless (exists $self->{interface_iid_nul});
	$self->{interface_iid} = {} unless (exists $self->{interface_iid});
	my $fullname = $entry->{name_space} . "::" . $entry->{name};
	if ($entry->{iid}->_is_nul()) {
		return if (exists $self->{interface_iid_nul}->{$fullname});
		foreach (values %{$self->{interface_iid}}) {
			return if ($fullname eq $_->{name_space} . "::" . $_->{name});
		}
		$self->{interface_iid_nul}->{$fullname} = $entry;
	} else {
		my $iid = $entry->{iid}->stringify();
		if (exists $self->{interface_iid}->{$iid}) {
			return if (defined $self->{interface_iid}->{$iid}->{interface_descriptor});
		} else {
			delete $self->{interface_iid_nul}->{$fullname}
					if (exists $self->{interface_iid_nul}->{$fullname});
			foreach (values %{$self->{interface_iid}}) {
				croak "ERROR: found duplicate definition of interface $fullname with iids \n"
						if ($fullname eq $_->{name_space} . "::" . $_->{name});
			}
		}
		$self->{interface_iid}->{$iid} = $entry;
	}
}

sub indexe {
	my $self = shift;
	foreach my $itf (values %{$self->{interface_iid}}) {
		next unless (defined $itf->{interface_descriptor});		# ISupport
		my $desc = $itf->{interface_descriptor};
		$desc->{parent_interface_index} = $self->_find_itf($desc->{parent_interface});
		foreach my $method (@{$desc->{method_descriptors}}) {
			foreach my $param (@{$method->{params}}) {
				my $type = $param->{type};
				if ($type->{tag} == XPT::InterfaceTypeDescriptor) {
					$type->{interface_index} = $self->_find_itf($type->{interface});
				}
			}
		}
	}
}

sub _find_itf {
	my $self = shift;
	my ($itf) = @_;
	return 0 unless (defined $itf);
	my @interface_directory = $self->_interface_directory();
	my $idx = 1;
	foreach (@interface_directory) {
		if (ref $itf) {
			if        ( $_->{name_space} eq $itf->{name_space}
					and $_->{name} eq $itf->{name} ) {
				return $idx;
			}
		} else {
			if ($itf eq $_->{name_space} . "::" . $_->{name}) {
				return $idx;
			}
		}
		$idx ++;
	}
	if (ref $itf) {
		croak "ERROR: interface $itf->{name_space}::$itf->{name} not found\n";
	} else {
		croak "ERROR: interface $itf not found\n";
	}
}

###############################################################################

package XPT::InterfaceDirectoryEntry;

use base qw(XPT);

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $iid = XPT::IID::demarshal($r_buffer, $r_offset);
	my $name = XPT::ReadCString($r_buffer, $r_offset);
	my $name_space = XPT::ReadCString($r_buffer, $r_offset);
	my $interface_descriptor_offset = XPT::Read32($r_buffer, $r_offset);
	my $interface_descriptor = undef;
	if ($interface_descriptor_offset) {
		my $offset = $XPT::data_pool_offset + $interface_descriptor_offset - 1;
		$interface_descriptor = XPT::InterfaceDescriptor::demarshal($r_buffer, \$offset);
	}

	return new XPT::InterfaceDirectoryEntry(
			iid						=> $iid,
			name					=> $name,
			name_space				=> $name_space,
			interface_descriptor	=> $interface_descriptor,
	);
}

sub marshal {
	my $self = shift;
	my $buffer = $self->{iid}->marshal();
	$buffer .= XPT::WriteCString($self->{name});
	$buffer .= XPT::WriteCString($self->{name_space});
	if (defined $self->{interface_descriptor}) {
		$buffer .= $self->{interface_descriptor}->marshal();
	} else {
		$buffer .= XPT::Write32(0);
	}
	return $buffer;
}

sub stringify {
	my $self = shift;
	my ($indent) = @_;
	$indent = "   " unless (defined $indent);
	my $new_indent = $indent . "   ";

	my $str = "";
	my $iid = $self->{iid}->stringify();
	if ($XPT::stringify_verbose) {
		my $name_space = $self->{name_space} || "none";
		$str .= $indent . "IID:                             " . $iid . "\n";
		$str .= $indent . "Name:                            " . $self->{name} . "\n";
		$str .= $indent . "Namespace:                       " . $name_space . "\n";
		$str .= $indent . "Descriptor:\n";
	} else {
		$str .= $indent . "- " . $self->{name_space} . "::" . $self->{name};
		$str .= " (" . $iid . "):\n";
	}
	if (defined $self->{interface_descriptor}) {
		$str .= $self->{interface_descriptor}->stringify($new_indent);
	} else {
		$str .= $indent . "   [Unresolved]\n";
	}
	return $str;
}

###############################################################################

package XPT::InterfaceDescriptor;

use base qw(XPT);

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $parent_interface_index = XPT::Read16($r_buffer, $r_offset);
	my @method_descriptors = ();
	my @const_descriptors = ();
	my $flags = 0;
	eval {
		my $num_methods = XPT::Read16($r_buffer, $r_offset);
		while ($num_methods --) {
			my $method = XPT::MethodDescriptor::demarshal($r_buffer, $r_offset);
			push @method_descriptors, $method;
		}
		my $num_constants = XPT::Read16($r_buffer, $r_offset);
		while ($num_constants --) {
			my $const = XPT::ConstDescriptor::demarshal($r_buffer, $r_offset);
			push @const_descriptors, $const;
		}
		$flags = XPT::Read8($r_buffer, $r_offset);
	};
	if ($@) {
		$XPT::demarshal_retcode = 1;
		if ($XPT::demarshal_not_abort) {
			warn $@;
		} else {
			die $@;
		}
	}

	return new XPT::InterfaceDescriptor(
			parent_interface_index	=> $parent_interface_index,
			method_descriptors		=> \@method_descriptors,
			const_descriptors		=> \@const_descriptors,
			is_scriptable			=> ($flags & 0x80) ? 1 : 0,
			is_function				=> ($flags & 0x40) ? 1 : 0,
	);
}

sub marshal {
	my $self = shift;
	my $method_descriptors = "";
	foreach (@{$self->{method_descriptors}}) {
		$method_descriptors .= $_->marshal();
	}
	my $const_descriptors = "";
	foreach (@{$self->{const_descriptors}}) {
		$const_descriptors .= $_->marshal();
	}
	my $flags = 0;
	$flags |= 0x80 if ($self->{is_scriptable});
	$flags |= 0x40 if ($self->{is_function});
	my $offset = 1 + length($XPT::data_pool);
	$XPT::data_pool .= XPT::Write16($self->{parent_interface_index});
	$XPT::data_pool .= XPT::Write16(scalar(@{$self->{method_descriptors}}));
	$XPT::data_pool .= $method_descriptors;
	$XPT::data_pool .= XPT::Write16(scalar(@{$self->{const_descriptors}}));
	$XPT::data_pool .= $const_descriptors;
	$XPT::data_pool .= XPT::Write8($flags);
	return XPT::Write32($offset);
}

sub stringify {
	my $self = shift;
	my ($indent) = @_;
	$indent = "  " unless (defined $indent);
	my $new_indent = $indent . "   ";
	my $more_indent = $new_indent . "   ";

	my $str = "";
	if ($self->{parent_interface_index}) {
		my $name;
		if (defined $self->{parent_interface}) {
			my $itf = $self->{parent_interface};
			if (ref $itf) {
				$name = $itf->{name_space} . "::" . $itf->{name};
			} else {
				$name = $itf;
			}
		} else {
			$name = "UNKNOWN_INTERFACE";
		}
		$str .= $indent . "Parent: " . $name . "\n"
	}
	$str .= $indent . "Flags:\n";
	$str .= $new_indent . "Scriptable: " . ($self->{is_scriptable} ? "TRUE" : "FALSE") . "\n";
	$str .= $new_indent . "Function: " . ($self->{is_function} ? "TRUE" : "FALSE") . "\n";
	if ($XPT::stringify_verbose and exists $self->{parent_interface_index}) {
		$str .= $indent . "Index of parent interface (in data pool): ";
			$str .= $self->{parent_interface_index} . "\n";
	}
	if (scalar @{$self->{method_descriptors}}) {
		if ($XPT::stringify_verbose) {
			$str .= $indent . "# of Method Descriptors:                   ";
				$str .= scalar(@{$self->{method_descriptors}}) . "\n";
		} else {
			$str .= $indent . "Methods:\n";
		}
		my $nb = 0;
		foreach (@{$self->{method_descriptors}}) {
			if ($XPT::stringify_verbose) {
				$str .= $new_indent . "Method #" . $nb ++ . ":\n";
				$str .= $_->stringify($more_indent);
			} else {
				$str .= $_->stringify($new_indent);
			}
		}
	} else {
		$str .= $indent . "Methods:\n";
		$str .= $new_indent . "No Methods\n";
	}
	if (scalar @{$self->{const_descriptors}}) {
		if ($XPT::stringify_verbose) {
			$str .= $indent . "# of Constant Descriptors:                  ";
				$str .= scalar(@{$self->{const_descriptors}}) . "\n";
		} else {
			$str .= $indent . "Constants:\n";
		}
		my $nb = 0;
		foreach (@{$self->{const_descriptors}}) {
			if ($XPT::stringify_verbose) {
				$str .= $new_indent . "Constant #" . $nb ++ . ":\n";
				$str .= $_->stringify($more_indent);
			} else {
				$str .= $_->stringify($new_indent);
			}
		}
	} else {
		$str .= $indent . "Constants:\n";
		$str .= $new_indent . "No Constants\n";
	}
	return $str;
}

###############################################################################

package XPT::ConstDescriptor;

use base qw(XPT);

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $name = XPT::ReadCString($r_buffer, $r_offset);
	my $type = XPT::TypeDescriptor::demarshal($r_buffer, $r_offset);
	if ($type->{is_pointer}) {
		die "illegal type for const ! (is_pointer)\n";
	}
	my $value = undef;
	if      ($type->{tag} == XPT::int8) {
		$value = XPT::Read8($r_buffer, $r_offset);
		$value -= 256 if ($value > 127);
	} elsif ($type->{tag} == XPT::int16) {
		$value = XPT::Read16($r_buffer, $r_offset);
		$value -= 65536 if ($value > 32277);
	} elsif ($type->{tag} == XPT::int32) {
		$value = XPT::Read32($r_buffer, $r_offset);
		$value -= 4294967295 if ($value > 2147483647);
	} elsif ($type->{tag} == XPT::int64) {
		$value = XPT::Read64($r_buffer, $r_offset);
		# unsupported
	} elsif ($type->{tag} == XPT::uint8) {
		$value = XPT::Read8($r_buffer, $r_offset);
	} elsif ($type->{tag} == XPT::uint16) {
		$value = XPT::Read16($r_buffer, $r_offset);
	} elsif ($type->{tag} == XPT::uint32) {
		$value = XPT::Read32($r_buffer, $r_offset);
	} elsif ($type->{tag} == XPT::uint64) {
		$value = XPT::Read64($r_buffer, $r_offset);
		# unsupported
	} elsif ($type->{tag} == XPT::char) {
		$value = chr(XPT::Read8($r_buffer, $r_offset));
	} elsif ($type->{tag} == XPT::wchar_t) {
		$value = chr(XPT::Read16($r_buffer, $r_offset));
	} else {
		die "illegal type for const ! ($type->{tag})\n";
	}

	return new XPT::ConstDescriptor(
			name					=> $name,
			type					=> $type,
			value					=> $value,
	);
}

sub marshal {
	my $self = shift;
	my $type = $self->{type};
	my $value = $self->{value};
	my $buffer = XPT::WriteCString($self->{name});
	$buffer .= $type->marshal();
	if      ($type->{tag} == XPT::int8) {
		$value += 256 if ($value < 0);
		$buffer .= XPT::Write8($value);
	} elsif ($type->{tag} == XPT::int16) {
		$value += 65536 if ($value < 0);
		$buffer .= XPT::Write16($value);
	} elsif ($type->{tag} == XPT::int32) {
		$value += 4294967295 if ($value < 0);
		$buffer .= XPT::Write32($value);
	} elsif ($type->{tag} == XPT::int64) {
		$buffer .= XPT::Write64($value);
		# unsupported
	} elsif ($type->{tag} == XPT::uint8) {
		$buffer .= XPT::Write8($value);
	} elsif ($type->{tag} == XPT::uint16) {
		$buffer .= XPT::Write16($value);
	} elsif ($type->{tag} == XPT::uint32) {
		$buffer .= XPT::Write32($value);
	} elsif ($type->{tag} == XPT::uint64) {
		$buffer .= XPT::Write64($value);
		# unsupported
	} elsif ($type->{tag} == XPT::char) {
		$buffer .= XPT::Write8(ord $value);
	} elsif ($type->{tag} == XPT::wchar_t) {
		$buffer .= XPT::Write16(ord $value);
	} else {
		die "illegal type for const ! ($type->{tag})\n";
	}
	return $buffer;
}

sub stringify {
	my $self = shift;
	my ($indent) = @_;
	$indent = "  " unless (defined $indent);
	my $new_indent = $indent . "   ";

	my $str = "";
	if ($XPT::stringify_verbose) {
		$str .= $indent . "Name:   " . $self->{name} . "\n";
		$str .= $indent . "Type Descriptor: \n";
		$str .= $self->{type}->stringify($new_indent);
		$str .= $indent . "Value:  ";
	} else {
		$str .= $indent . $self->{type}->stringify() . " " . $self->{name} . " = ";
	}
	$str .= $self->{value};
	if ($XPT::stringify_verbose) {
		$str .= "\n";
	} else {
		$str .= ";\n";
	}
	return $str;
}

###############################################################################

package XPT::MethodDescriptor;

use base qw(XPT);

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $flags = XPT::Read8($r_buffer, $r_offset);
	my $name = XPT::ReadCString($r_buffer, $r_offset);
	my $num_args = XPT::Read8($r_buffer, $r_offset);
	my @params = ();
	while ($num_args --) {
		my $param = XPT::ParamDescriptor::demarshal($r_buffer, $r_offset);
		push @params, $param;
	}
	my $result = XPT::ParamDescriptor::demarshal($r_buffer, $r_offset);

	return new XPT::MethodDescriptor(
			is_getter				=> ($flags & 0x80) ? 1 : 0,
			is_setter				=> ($flags & 0x40) ? 1 : 0,
			is_not_xpcom			=> ($flags & 0x20) ? 1 : 0,
			is_constructor			=> ($flags & 0x10) ? 1 : 0,
			is_hidden				=> ($flags & 0x08) ? 1 : 0,
			name					=> $name,
			params					=> \@params,
			result					=> $result,
	);
}

sub marshal {
	my $self = shift;
	my $flags = 0;
	$flags |= 0x80 if ($self->{is_getter});
	$flags |= 0x40 if ($self->{is_setter});
	$flags |= 0x20 if ($self->{is_not_xpcom});
	$flags |= 0x10 if ($self->{is_constructor});
	$flags |= 0x08 if ($self->{is_hidden});
	my $buffer = XPT::Write8($flags);
	$buffer .= XPT::WriteCString($self->{name});
	$buffer .= XPT::Write8(scalar(@{$self->{params}}));
	foreach (@{$self->{params}}) {
		$buffer .= $_->marshal();
	}
	$buffer .= $self->{result}->marshal();
	return $buffer;
}

sub stringify {
	my $self = shift;
	my ($indent) = @_;
	$indent = "      " unless (defined $indent);
	my $new_indent = $indent . "   ";
	my $more_indent = $new_indent . "   ";

	my $str = "";
	if ($XPT::stringify_verbose) {
		$str .= $indent . "Name:             " . $self->{name} . "\n";
		$str .= $indent . "Is Getter?        " . ($self->{is_getter} ? "TRUE" : "FALSE") . "\n";
		$str .= $indent . "Is Setter?        " . ($self->{is_setter} ? "TRUE" : "FALSE") . "\n";
		$str .= $indent . "Is NotXPCOM?      " . ($self->{is_not_xpcom} ? "TRUE" : "FALSE") . "\n";
		$str .= $indent . "Is Constructor?   " . ($self->{is_constructor} ? "TRUE" : "FALSE") . "\n";
		$str .= $indent . "Is Hidden?        " . ($self->{is_hidden} ? "TRUE" : "FALSE") . "\n";
		$str .= $indent . "# of arguments:   " . scalar(@{$self->{params}}) . "\n";
		$str .= $indent . "Parameter Descriptors:\n";
		my $nb = 0;
		foreach (@{$self->{params}})  {
			$str .= $new_indent . "Parameter #" . $nb ++ . ":\n";
			if (!$_->{in} and !$_->{out}) {
				$str .= "XXX\n";
				$XPT::param_problems = 1;
			}
			$str .= $_->stringify($more_indent);
		}
		$str .= $indent . "Result:\n";
		if (        $self->{result}->{type}->{tag} != XPT::void
				and $self->{result}->{type}->{tag} != XPT::uint32) {
			$str .= "XXX\n";
			$XPT::param_problems = 1;
		}
		$str .= $self->{result}->stringify($new_indent);
	} else {
		$str .= substr($indent, 6);
		$str .= ($self->{is_getter} ? "G" :  " ");
		$str .= ($self->{is_setter} ? "S" :  " ");
		$str .= ($self->{is_hidden} ? "H" :  " ");
		$str .= ($self->{is_not_xpcom} ? "N" :  " ");
		$str .= ($self->{is_constructor} ? "C" :  " ");
		$str .= " " . $self->{result}->{type}->stringify() . " " . $self->{name} . "(";
		my $first = 1;
		foreach (@{$self->{params}})  {
			$str .= ", " unless ($first);
			if ($_->{in}) {
				$str .= "in";
				if ($_->{out}) {
					$str .= "out ";
					$str .= "retval " if ($_->{retval});
					$str .= "shared " if ($_->{shared});
				} else {
					$str .= " ";
					$str .= "dipper " if ($_->{dipper});
					$str .= "retval " if ($_->{retval});
				}
			} else {
				if ($_->{out}) {
					$str .= "out ";
					$str .= "retval " if ($_->{retval});
					$str .= "shared " if ($_->{shared});
				} else {
					$XPT::params_problems = 1;
					$str .= "XXX ";
				}
			}
			$str .= $_->{type}->stringify();
			$first = 0;
		}
		$str .= ");\n";
	}
	return $str;
}

###############################################################################

package XPT::ParamDescriptor;

use base qw(XPT);

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $flags = XPT::Read8($r_buffer, $r_offset);
	my $type = XPT::TypeDescriptor::demarshal($r_buffer, $r_offset);

	return new XPT::ParamDescriptor(
			in						=> ($flags & 0x80) ? 1 : 0,
			out						=> ($flags & 0x40) ? 1 : 0,
			retval					=> ($flags & 0x20) ? 1 : 0,
			shared					=> ($flags & 0x10) ? 1 : 0,
			dipper					=> ($flags & 0x08) ? 1 : 0,
			type					=> $type,
	);
}

sub marshal {
	my $self = shift;
	my $flags = 0;
	$flags |= 0x80 if ($self->{in});
	$flags |= 0x40 if ($self->{out});
	$flags |= 0x20 if ($self->{retval});
	$flags |= 0x10 if ($self->{shared});
	$flags |= 0x08 if ($self->{dipper});
	my $buffer = XPT::Write8($flags);
	$buffer .= $self->{type}->marshal();
	return $buffer;
}

sub stringify {			# allways VERBOSE
	my $self = shift;
	my ($indent) = @_;
	$indent = "  " unless (defined $indent);
	my $new_indent = $indent . "   ";

	my $str = "";
	$str .= $indent . "In Param?   " . ($self->{in} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Out Param?  " . ($self->{out} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Retval?     " . ($self->{retval} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Shared?     " . ($self->{shared} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Dipper?     " . ($self->{dipper} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Type Descriptor:\n";
	$str .= $self->{type}->stringify($new_indent);
	return $str;
}

###############################################################################

package XPT::TypeDescriptor;

use base qw(XPT);

use Carp;

use constant TYPE_ARRAY => [
	"int8",        "int16",       "int32",       "int64",
	"uint8",       "uint16",      "uint32",      "uint64",
	"float",       "double",      "boolean",     "char",
	"wchar_t",     "void",        "reserved",    "reserved",
	"reserved",    "reserved",    "reserved",    "reserved",
	"reserved",    "reserved",    "reserved",    "reserved",
	"reserved",    "reserved",    "reserved",    "reserved",
	"reserved",    "reserved",    "reserved",    "reserved"
];

use constant PTYPE_ARRAY => [
	"int8 *",      "int16 *",     "int32 *",     "int64 *",
	"uint8 *",     "uint16 *",    "uint32 *",    "uint64 *",
	"float *",     "double *",    "boolean *",   "char *",
	"wchar_t *",   "void *",      "nsIID *",     "DOMString *",
	"string",      "wstring",     "Interface *", "InterfaceIs *",
	"array",       "string_s",    "wstring_s",   "UTF8String *",
	"CString *",   "AString *",   "reserved",    "reserved",
	"reserved",    "reserved",    "reserved",    "reserved"
];

use constant RTYPE_ARRAY => [
	"int8 &",      "int16 &",     "int32 &",     "int64 &",
	"uint8 &",     "uint16 &",    "uint32 &",    "uint64 &",
	"float &",     "double &",    "boolean &",   "char &",
	"wchar_t &",   "void &",      "nsIID &",     "DOMString &",
	"string &",    "wstring &",   "Interface &", "InterfaceIs &",
	"array &",     "string_s &",  "wstring_s &", "UTF8String &",
	"CString &",   "AString &",   "reserved",    "reserved",
	"reserved",    "reserved",    "reserved",    "reserved"
];

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $flags = XPT::Read8($r_buffer, $r_offset);

	my $type = new XPT::TypeDescriptor(
			is_pointer				=> ($flags & 0x80) ? 1 : 0,
			is_unique_pointer		=> ($flags & 0x40) ? 1 : 0,
			is_reference			=> ($flags & 0x20) ? 1 : 0,
			tag						=> $flags & 0x1f,
	);

	if      ($type->{tag} <  XPT::InterfaceTypeDescriptor) {
		# SimpleTypeDescriptor
	} elsif ($type->{tag} == XPT::InterfaceTypeDescriptor) {
		croak "is_pointer is not set!\n"
				unless ($type->{is_pointer});
		$type->{interface_index} = XPT::Read16($r_buffer, $r_offset);
	} elsif ($type->{tag} == XPT::InterfaceIsTypeDescriptor) {
		croak "is_pointer is not set!\n"
				unless ($type->{is_pointer});
		$type->{arg_num} = XPT::Read8($r_buffer, $r_offset);
	} elsif ($type->{tag} == XPT::ArrayTypeDescriptor) {
		croak "is_pointer is not set!\n"
				unless ($type->{is_pointer});
		$type->{size_is_arg_num} = XPT::Read8($r_buffer, $r_offset);
		$type->{length_is_arg_num} = XPT::Read8($r_buffer, $r_offset);
		$type->{type_descriptor} = XPT::TypeDescriptor::demarshal($r_buffer, $r_offset);
	} elsif ($type->{tag} == XPT::StringWithSizeTypeDescriptor) {
		croak "is_pointer is not set!\n"
				unless ($type->{is_pointer});
		$type->{size_is_arg_num} = XPT::Read8($r_buffer, $r_offset);
		$type->{length_is_arg_num} = XPT::Read8($r_buffer, $r_offset);
	} elsif ($type->{tag} == XPT::WideStringWithSizeTypeDescriptor) {
		croak "is_pointer is not set!\n"
				unless ($type->{is_pointer});
		$type->{size_is_arg_num} = XPT::Read8($r_buffer, $r_offset);
		$type->{length_is_arg_num} = XPT::Read8($r_buffer, $r_offset);
	} else {
		# reserved
	}
	return $type;
}

sub marshal {
	my $self = shift;
	my $flags = $self->{tag};
	$flags |= 0x80 if ($self->{is_pointer});
	$flags |= 0x40 if ($self->{is_unique_pointer});
	$flags |= 0x20 if ($self->{is_reference});
	my $buffer = XPT::Write8($flags);
	if      ($self->{tag} <  XPT::InterfaceTypeDescriptor) {
		# SimpleTypeDescriptor
	} elsif ($self->{tag} == XPT::InterfaceTypeDescriptor) {
		$buffer .= XPT::Write16($self->{interface_index});
	} elsif ($self->{tag} == XPT::InterfaceIsTypeDescriptor) {
		$buffer .= XPT::Write8($self->{arg_num});
	} elsif ($self->{tag} == XPT::ArrayTypeDescriptor) {
		$buffer .= XPT::Write8($self->{size_is_arg_num});
		$buffer .= XPT::Write8($self->{length_is_arg_num});
		$buffer .= $self->{type_descriptor}->marshal();
	} elsif ($self->{tag} == XPT::StringWithSizeTypeDescriptor) {
		$buffer .= XPT::Write8($self->{size_is_arg_num});
		$buffer .= XPT::Write8($self->{length_is_arg_num});
	} elsif ($self->{tag} == XPT::WideStringWithSizeTypeDescriptor) {
		$buffer .= XPT::Write8($self->{size_is_arg_num});
		$buffer .= XPT::Write8($self->{length_is_arg_num});
	} else {
		# reserved
	}
	return $buffer;
}

sub stringify {
	my $self = shift;
	return $self->_get_string()
			unless ($XPT::stringify_verbose);
	my ($indent) = @_;
	$indent = "  " unless (defined $indent);
	my $new_indent = $indent . "   ";

	my $str = "";
	$str .= $indent . "Is Pointer?        " . ($self->{is_pointer} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Is Unique Pointer? " . ($self->{is_unique_pointer} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Is Reference?      " . ($self->{is_reference} ? "TRUE" : "FALSE") . "\n";
	$str .= $indent . "Tag:               " . $self->{tag} . "\n";

	if       ( $self->{tag} == XPT::StringWithSizeTypeDescriptor
			or $self->{tag} == XPT::WideStringWithSizeTypeDescriptor ) {
		$str .= $indent . " - size in arg " . $self->{size_is_arg_num};
			$str .= " and length in arg " . $self->{length_is_arg_num} . "\n";
	}
	if ($self->{tag} == XPT::InterfaceTypeDescriptor) {
		$str .= $indent . "InterfaceTypeDescriptor:\n";
		$str .= $new_indent . "Index of IDE:             " . $self->{interface_index} . "\n";
	}
	if ($self->{tag} == XPT::InterfaceIsTypeDescriptor) {
		$str .= $indent . "InterfaceTypeDescriptor:\n";
		$str .= $new_indent . "Index of Method Argument: " . $self->{arg_num} . "\n";
	}
	return $str;
}

sub _get_string {
	my $self = shift;

	if ($self->{tag} == XPT::ArrayTypeDescriptor) {
		return $self->{type_descriptor}->_get_string() . " []";
	}

	my $str = "";
	if ($self->{tag} == XPT::InterfaceTypeDescriptor) {
		if (defined $self->{interface}) {
			$str = $self->{interface}->{name};
		} else {
			$str = "UNKNOWN_INTERFACE";
		}
	} elsif ($self->{is_pointer}) {
		if ($self->{is_reference}) {
			$str = RTYPE_ARRAY->[$self->{tag}];
		} else {
			$str = PTYPE_ARRAY->[$self->{tag}];
		}
	} else {
		$str = TYPE_ARRAY->[$self->{tag}];
	}

	return $str;
}

###############################################################################

package XPT::Annotation;

use base qw(XPT);

sub demarshal {
	my ($r_buffer, $r_offset) = @_;
	my $annotation = new XPT::Annotation();

	my $flags = XPT::Read8($r_buffer, $r_offset);
	my $tag = $flags & 0x7f;

	if ($tag) {
		my $creator = XPT::ReadStringInline($r_buffer, $r_offset);
		my $private_data = XPT::ReadStringInline($r_buffer, $r_offset);

		return new XPT::Annotation(
				is_last					=> ($flags & 0x80) ? 1 : 0,
				tag						=> $tag,
				creator					=> $creator,
				private_data			=> $private_data,
		);
	} else {
		return new XPT::Annotation(
				is_last					=> ($flags & 0x80) ? 1 : 0,
				tag						=> 0,
		);
	}
}

sub marshal {
	my $self = shift;
	my $tag = $self->{tag};
	$tag += 0x80 if ($self->{is_last});
	my $buffer = XPT::Write8($tag);
	if ($self->{tag}) {
		$buffer .= XPT::WriteStringInline($self->{creator});
		$buffer .= XPT::WriteStringInline($self->{private_data});
	}
	return $buffer;
}

sub stringify {
	my $self = shift;
	my ($indent) = @_;
	$indent = "   " unless (defined $indent);
	my $new_indent = $indent . "   ";

	my $str = "";
	if ($self->{tag}) {
		if ($XPT::stringify_verbose) {
			$str .= " is private.\n";
		} else {
			$str .= ":\n";
		}
		$indent .= "   ";
		$str .= $new_indent . "Creator:      " . $self->{creator} . "\n";
		$str .= $new_indent . "Private Data: " . $self->{private_data} . "\n";
	} else {
		$str .= " is empty.\n";
	}
	return $str;
}

###############################################################################

package XPT::IID;

use Carp;

use base qw(XPT);

use constant IID_NUL	=> "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $data = shift;
	my $self = \$data;
	bless($self, $class);
	return $self
}

sub demarshal {
	my ($r_buffer, $r_offset) = @_;

	my $iid = XPT::ReadBuffer($r_buffer, $r_offset, 16);

	return new XPT::IID($iid);
}

sub marshal {
	my $self = shift;
	croak "bad length.\n"
			unless (length ${$self} == length XPT::File::MAGIC);
	return ${$self};
}

sub stringify {
	my $self = shift;
	my $str = "";
	my $idx = 0;
	foreach (split //, ${$self}) {
		$str .= sprintf("%02x", ord $_);
		$idx ++;
		$str .= "-" if ($idx == 4 or $idx == 6 or $idx == 8 or $idx == 10);
	}
	return $str;
}

sub _is_nul {
	my $self = shift;
	return ${$self} eq IID_NUL;
}

##############################################################################

package CORBA::XPIDL::xptVisitor;

use File::Basename;
use POSIX qw(ctime);

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	my ($parser) = @_;
	$self->{srcname} = $parser->YYData->{srcname};
	$self->{symbtab} = $parser->YYData->{symbtab};
	$self->{emit_typelib_annotations} = $parser->YYData->{opt_a};
	$self->{typelib} = $parser->YYData->{opt_t};
	my $filename;
	if ($parser->YYData->{opt_e}) {
		$filename = $parser->YYData->{opt_e};
	} else {
		if ($parser->YYData->{opt_o}) {
			$filename = $parser->YYData->{opt_o} . ".xpt";
		} else {
			$filename = basename($self->{srcname}, ".idl") . ".xpt";
		}
	}
	$self->{outfile} = $filename;
	return $self;
}

sub _get_defn {
	my $self = shift;
	my ($defn) = @_;
	if (ref $defn) {
		return $defn;
	} else {
		return $self->{symbtab}->Lookup($defn);
	}
}

sub _is_dipper {
	my $self = shift;
	my ($node) = @_;	# type
	return     $node->hasProperty("domstring")
			|| $node->hasProperty("utf8string")
			|| $node->hasProperty("cstring")
			|| $node->hasProperty("astring");
}

sub _arg_num {
	my $self = shift;
	my ($name, $node) = @_;
	my $count = 0;
	foreach (@{$node->{list_param}}) {
		return $count
				if ($_->{idf} eq $name);
		$count ++;
	}
	warn __PACKAGE__,"::_arg_num : can't found argument ($name) in method '$node->{idf}'.\n";
}

#
#	3.5		OMG IDL Specification
#

sub visitSpecification {
	my $self = shift;
	my ($node) = @_;

	my $major_version = substr($self->{typelib}, 0, 1);
	my $minor_version = substr($self->{typelib}, 2, 1);
	$self->{xpt} = new XPT::File(
			magic			=> XPT::File::MAGIC,
			major_version	=> $major_version,
			minor_version	=> $minor_version,
	);
	foreach (@{$node->{list_decl}}) {
		$self->_get_defn($_)->visit($self);
	}
	$self->{xpt}->indexe();

	if ($self->{emit_typelib_annotations}) {
		my $creator = "xpidl.pl " . $CORBA::XPIDL::check::VERSION;
		my $data = "Created from " . $self->{srcname} .
		           "\nCreation date: " . POSIX::ctime(time()) . "Interfaces:";
		foreach (sort keys %{$self->{xpt}->{interface_iid}}) {
			my $itf = ${$self->{xpt}->{interface_iid}}{$_};
			next unless (defined $itf->{interface_descriptor});
			$data .= " " . $itf->{name};
		}
		my $anno = new XPT::Annotation(
				tag						=> 1,
				creator					=> $creator,
				private_data			=> $data,
		);
		$self->{xpt}->add_annotation($anno);
	}
	$self->{xpt}->terminate_annotations();

#	print $self->{xpt}->stringify();
	open OUT, ">$self->{outfile}"
			or die "FAILED: can't open $self->{outfile}\n";
	binmode OUT, ":raw";
	print OUT $self->{xpt}->marshal();
	close OUT;
}

#
#	3.7		Module Declaration
#

sub visitModules {
	my $self = shift;
	my ($node) = @_;
	foreach (@{$node->{list_decl}}) {
		$self->_get_defn($_)->visit($self);
	}
}

sub visitModule {
	my $self = shift;
	my ($node) = @_;
	if ($self->{srcname} eq $node->{filename}) {
		foreach (@{$node->{list_decl}}) {
			$self->_get_defn($_)->visit($self);
		}
	}
}

#
#	3.8		Interface Declaration
#

sub visitRegularInterface {
	my $self = shift;
	my ($node) = @_;
	if ($self->{srcname} eq $node->{filename}) {
		my $parent_interface_name;
		if (exists $node->{inheritance}) {
			my $base = $self->_get_defn(${$node->{inheritance}->{list_interface}}[0]);
			my $namespace = $base->getProperty("namespace") || "";
			$parent_interface_name = $namespace . "::" . $base->{idf};
			$self->_add_interface($base);
		}
		my $interface_descriptor = new XPT::InterfaceDescriptor(
				parent_interface		=> $parent_interface_name,
				method_descriptors		=> [],
				const_descriptors		=> [],
				is_scriptable			=> $node->hasProperty("scriptable"),
				is_function				=> $node->hasProperty("function"),
		);
		$self->{itf} = $interface_descriptor;
		foreach (@{$node->{list_decl}}) {
			$self->_get_defn($_)->visit($self);
		}
		$self->_add_interface($node, $interface_descriptor);
	}
}

sub _add_interface {
	my $self = shift;
	my ($node, $desc) = @_;
	my $iid = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";
	my $str_iid = $node->getProperty("uuid");
	if (defined $str_iid) {
		$str_iid =~ s/-//g;
		$iid = "";
		while ($str_iid) {
			$iid .= chr(hex(substr $str_iid, 0, 2));
			$str_iid = substr $str_iid, 2;
		}
	}
	my $name = $node->{idf};
	my $namespace = $node->getProperty("namespace") || "";
	my $entry = new XPT::InterfaceDirectoryEntry(
			iid						=> new XPT::IID($iid),
			name					=> $name,
			name_space				=> $namespace,
			interface_descriptor	=> $desc,
	);
	$self->{xpt}->add_interface($entry);
}

sub visitForwardRegularInterface {
	my $self = shift;
	my ($node) = @_;
	if ($self->{srcname} eq $node->{filename}) {
		$self->_add_interface($node);
	}
}

sub visitBaseInterface {
	# empty
}

sub visitForwardBaseInterface {
	# empty
}

#
#	3.10	Constant Declaration
#

sub visitConstant {
	my $self = shift;
	my ($node) = @_;
	my $type = $self->_get_defn($node->{type});
	my $desc = $self->_type($type);
	my $value = $node->{value}->{value};
	my $cst = new XPT::ConstDescriptor(
			name					=> $node->{idf},
			type					=> $desc,
			value					=> $value,
	);
	push @{$self->{itf}->{const_descriptors}}, $cst;
}

#
#	3.11	Type Declaration
#

sub visitTypeDeclarators {
	# empty
}

sub visitNativeType {
	# empty
}

sub _type {
	my $self = shift;
	my ($node, $param, $method) = @_;

	my $is_array = defined $method && $param->hasProperty("array");
	my $type = $node;
	while ($type->isa('TypeDeclarator')) {
		$type = $self->_get_defn($type->{type});
	}
	my %hash;
	my $iid_is = $param->getProperty("iid_is") if (defined $param);

	if (     $type->isa('IntegerType')) {
		if      ($type->{value} eq 'short') {
			$hash{tag} = XPT::int16;
		} elsif ($type->{value} eq 'unsigned short') {
			$hash{tag} = XPT::uint16;
		} elsif ($type->{value} eq 'long') {
			$hash{tag} = XPT::int32;
		} elsif ($type->{value} eq 'unsigned long') {
			$hash{tag} = XPT::uint32;
		} elsif ($type->{value} eq 'long long') {
			$hash{tag} = XPT::int64;
		} elsif ($type->{value} eq 'unsigned long long') {
			$hash{tag} = XPT::uint64;
		} else {
			warn __PACKAGE__,"::_type (IntegerType) $node->{value}.\n";
		}
	} elsif ($type->isa('OctetType')) {
		$hash{tag} = XPT::uint8;
	} elsif ($type->isa('FloatingPtType')) {
		if (     $type->{value} eq "float") {
			$hash{tag} = XPT::float;
		} elsif ($type->{value} eq "double") {
			$hash{tag} = XPT::double;
		} else {
			warn __PACKAGE__,"::_type (FloatingPtType) $node->{value}.\n";
		}
	} elsif ($type->isa('BooleanType')) {
		$hash{tag} = XPT::boolean;
	} elsif ($type->isa('CharType')) {
		$hash{tag} = XPT::char;
	} elsif ($type->isa('WideCharType')) {
		$hash{tag} = XPT::wchar_t;
	} elsif ($type->isa('StringType')) {
		my $size_is = $param->getProperty("size_is")
				if (defined $param);
		if ($is_array or !defined $method or !defined $size_is) {
			$hash{tag} = XPT::pstring;
			$hash{is_pointer} = 1;
		} else {
			$hash{tag} = XPT::StringWithSizeTypeDescriptor;
			$hash{is_pointer} = 1;
			$hash{size_is_arg_num} = $self->_arg_num($size_is, $method);
			$hash{length_is_arg_num} = $hash{size_is_arg_num};
			my $length_is = $param->getProperty("length_is");
			$hash{length_is_arg_num} = $self->_arg_num($length_is, $method)
					if (defined $length_is);
		}
	} elsif ($type->isa('WideStringType')) {
		my $size_is = $param->getProperty("size_is")
				if (defined $param);
		if ($is_array or !defined $method or !defined $size_is) {
			$hash{tag} = XPT::pwstring;
			$hash{is_pointer} = 1;
		} else {
			$hash{tag} = XPT::WideStringWithSizeTypeDescriptor;
			$hash{is_pointer} = 1;
			$hash{size_is_arg_num} = $self->_arg_num($size_is, $method);
			$hash{length_is_arg_num} = $hash{size_is_arg_num};
			my $length_is = $param->getProperty("length_is");
			$hash{length_is_arg_num} = $self->_arg_num($length_is, $method)
					if (defined $length_is);
		}
	} elsif ($type->isa('NativeType') and !defined $iid_is) {
		if      ($node->hasProperty("nsid")) {
			$hash{tag} = XPT::nsIID;
			if      ($node->hasProperty("ref")) {
				$hash{is_pointer} = 1;
				$hash{is_reference} = 1;
			} elsif ($node->hasProperty("ptr")) {
				$hash{is_pointer} = 1;
			}
		} elsif ($node->hasProperty("domstring")) {
			$hash{tag} = XPT::domstring;
			$hash{is_pointer} = 1;
			if ($node->hasProperty("ref")) {
				$hash{is_reference} = 1;
			}
		} elsif ($node->hasProperty("astring")) {
			$hash{tag} = XPT::astring;
			$hash{is_pointer} = 1;
			if ($node->hasProperty("ref")) {
				$hash{is_reference} = 1;
			}
		} elsif ($node->hasProperty("utf8string")) {
			$hash{tag} = XPT::utf8string;
			$hash{is_pointer} = 1;
			if ($node->hasProperty("ref")) {
				$hash{is_reference} = 1;
			}
		} elsif ($node->hasProperty("cstring")) {
			$hash{tag} = XPT::cstring;
			$hash{is_pointer} = 1;
			if ($node->hasProperty("ref")) {
				$hash{is_reference} = 1;
			}
		} else {
			$hash{tag} = XPT::void;
			$hash{is_pointer} = 1;
		}
	} elsif (  $type->isa('RegularInterface')
			or $type->isa('ForwardRegularInterface')
			or $type->isa('NativeType') ) {
		if (defined $iid_is) {
			$hash{tag} = XPT::InterfaceIsTypeDescriptor;
			$hash{is_pointer} = 1;
			$hash{arg_num} = $self->_arg_num($iid_is, $method);
		} else {
			$self->_add_interface($type);
			my $namespace = $type->getProperty("namespace") || "";
			$hash{interface} = $namespace . "::" . $type->{idf};
			$hash{tag} = XPT::InterfaceTypeDescriptor;
			$hash{is_pointer} = 1;
		}
	} elsif ($type->isa('VoidType')) {
		$hash{tag} = XPT::void;
	}
	my $desc = new XPT::TypeDescriptor( %hash );

	if ($is_array) {
		# size_is is required
		my $size_is = $param->getProperty("size_is");
#		die "[array] requires [size_is()].\n"
#				unless (defined $size_is);
		my $size_is_arg_num = $self->_arg_num($size_is, $method);
		# length_is is optional
		my $length_is_arg_num = $size_is_arg_num;
		my $length_is = $param->getProperty("length_is");
		$length_is_arg_num = $self->_arg_num($size_is, $method)
				if (defined $length_is);
		return new XPT::TypeDescriptor(
				is_pointer				=> 1,
				is_unique_pointer		=> 0,
				is_reference			=> 0,
				tag						=> XPT::ArrayTypeDescriptor,
				size_is_arg_num			=> $size_is_arg_num,
				length_is_arg_num		=> $length_is_arg_num,
				type_descriptor			=> $desc,
		);
	} else {
		return $desc
	}
}

#
#	3.11.2	Constructed Types
#

sub visitStructType {
	# empty
}

sub visitUnionType {
	# empty
}

sub visitEnumType {
	# empty
}

#
#	3.12	Exception Declaration
#

sub visitException {
	# empty
}

#
#	3.13	Operation Declaration
#

sub visitOperation {
	my $self = shift;
	my ($node) = @_;
	my $notxpcom = $node->hasProperty("notxpcom");
	my @params = ();
	foreach (@{$node->{list_param}}) {
		push @params, $self->_param($_, $node);
	}
	my $type = $self->_get_defn($node->{type});
	my $result;
	if ($notxpcom) {
		$result = new XPT::ParamDescriptor(
				in						=> 0,
				out						=> 0,
				retval					=> 1,
				shared					=> 0,
				dipper					=> 0,
				type					=> $self->_type($type),
		);
	} else {
		unless ($type->isa('VoidType')) {
			my $dipper = $self->_is_dipper($type);
			my $desc = $self->_type($type);
			push @params, new XPT::ParamDescriptor(
					in						=> $dipper,
					out						=> !$dipper,
					retval					=> 1,
					shared					=> 0,
					dipper					=> $dipper,
					type					=> $desc,
			);
		}

		$result = $self->_ns_result();
	}
	my $method = new XPT::MethodDescriptor(
			is_getter				=> 0,
			is_setter				=> 0,
			is_not_xpcom			=> $notxpcom,
			is_constructor			=> 0,
			is_hidden				=> $node->hasProperty("noscript"),
			name					=> $node->{idf},
			params					=> \@params,
			result					=> $result,
	);
	push @{$self->{itf}->{method_descriptors}}, $method;
}

sub _param {
	my $self = shift;
	my ($node, $parent) = @_;
	my $type = $self->_get_defn($node->{type});
	my $in = 0;
	my $out = 0;
	if ($node->{attr} eq "in") {
		$in = 1;
	} elsif ($node->{attr} eq "out") {
		$out = 1;
	} elsif ($node->{attr} eq "inout") {
		$in = 1;
		$out = 1;
	}
#	my $dipper = $self->_is_dipper($type);
	my $dipper = $self->_is_dipper($node);
	if ($dipper and $out) {
		$out = 0;
		$in = 1;
	}
	my $desc = $self->_type($type, $node, $parent);
	return new XPT::ParamDescriptor(
			in						=> $in,
			out						=> $out,
			retval					=> $node->hasProperty("retval"),
			shared					=> $node->hasProperty("shared"),
			dipper					=> $dipper,
			type					=> $desc,
	);
}

sub _ns_result {
	my $self = shift;
	return new XPT::ParamDescriptor(
			in						=> 0,
			out						=> 0,
			retval					=> 0,
			shared					=> 0,
			dipper					=> 0,
			type					=> new XPT::TypeDescriptor(
					is_pointer				=> 0,
					is_unique_pointer		=> 0,
					is_reference			=> 0,
					tag						=> XPT::uint32,
			),
	);
}

#
#	3.14	Attribute Declaration
#

sub visitAttributes {
	my $self = shift;
	my ($node) = @_;
	foreach (@{$node->{list_decl}}) {
		$self->_get_defn($_)->visit($self);
	}
}

sub visitAttribute {
	my $self = shift;
	my ($node) = @_;
	my $type = $self->_get_defn($node->{type});
	my $dipper = $self->_is_dipper($type);
	my $getter = new XPT::MethodDescriptor(
			is_getter				=> 1,
			is_setter				=> 0,
#			is_not_xpcom			=> $node->hasProperty("notxpcom"),
			is_not_xpcom			=> 0,	# functionality or bug
			is_constructor			=> 0,
			is_hidden				=> $node->hasProperty("noscript"),
			name					=> $node->{idf},
			params					=> [
				new XPT::ParamDescriptor(
						in						=> $dipper,
						out						=> !$dipper,
						retval					=> 1,
						shared					=> 0,
						dipper					=> $dipper,
						type					=> $self->_type($type),
				)
			],
			result					=> $self->_ns_result(),
	);
	push @{$self->{itf}->{method_descriptors}}, $getter;
	unless (exists $node->{modifier}) {		# readonly
		my $setter = new XPT::MethodDescriptor(
				is_getter				=> 0,
				is_setter				=> 1,
#				is_not_xpcom			=> $node->hasProperty("notxpcom"),
				is_not_xpcom			=> 0,	# functionality or bug
				is_constructor			=> 0,
				is_hidden				=> $node->hasProperty("noscript"),
				name					=> $node->{idf},
				params					=> [
					new XPT::ParamDescriptor(
							in						=> 1,
							out						=> 0,
							retval					=> 0,
							shared					=> 0,
							dipper					=> 0,
							type					=> $self->_type($type),
					)
				],
				result					=> $self->_ns_result(),
		);
		push @{$self->{itf}->{method_descriptors}}, $setter;
	}
}

#
#	3.15	Repository Identity Related Declarations
#

sub visitTypeId {
	# empty
}

sub visitTypePrefix {
	# empty
}

#
#	XPIDL
#

sub visitCodeFragment {
	# empty
}

1;

