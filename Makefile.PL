use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'          => 'CORBA::XPIDL',
    'VERSION_FROM'  => 'check.pm',
    'ABSTRACT'      => 'XPIDL compiler (for Mozilla)',
    'PREREQ_PM'     => {
                        'CORBA::IDL::node'  => 2.40,
    },
    'PM'            => {
                        'check.pm'      => '$(INST_LIBDIR)/XPIDL/check.pm',
                        'doc.pm'        => '$(INST_LIBDIR)/XPIDL/doc.pm',
			'header.pm'     => '$(INST_LIBDIR)/XPIDL/header.pm',
                        'java.pm'       => '$(INST_LIBDIR)/XPIDL/java.pm',
                        'xpt.pm'        => '$(INST_LIBDIR)/XPIDL/xpt.pm',
    },
    'EXE_FILES'     => ['xpidl.pl', 'xpt_dump.pl', 'xpt_link.pl'],
    'AUTHOR'        => "Francois PERRAD (francois.perrad\@gadz.org)",
    'dist'          => {
                        'COMPRESS'      => 'gzip',
                        'SUFFIX'        => '.gz',
    },
);
