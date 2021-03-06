use File::Path();
use File::Glob();

# leftovers in old checkouts
unlink 'lib/DBIx/Class/Optional/Dependencies.pod'
  if -f 'lib/DBIx/Class/Optional/Dependencies.pod';
File::Path::rmtree([ '.generated_pod' ])
  if -d '.generated_pod';

my $pod_dir = 'maint/.Generated_Pod';
my $ver = Meta->version;

# cleanup the generated pod dir (again - kill leftovers from old checkouts)
if (-d $pod_dir) {
  File::Path::rmtree([ File::Glob::bsd_glob("$pod_dir/*") ]);
}
else {
  mkdir $pod_dir or die "Unable to create $pod_dir: $!";
}

# generate the OptDeps pod both in the clone-dir and during the makefile distdir
{
  print "Regenerating Optional/Dependencies.pod\n";

  eval {
    require DBIx::Class::Optional::Dependencies;
    DBIx::Class::Optional::Dependencies->_gen_pod ($ver, "$pod_dir/lib");
    1;
  }
    or
  printf ("FAILED!!! Subsequent `make dist` will fail. %s\n",
    $ENV{DBICDIST_DEBUG}
      ? "Full error: $@"
      : 'Re-run with $ENV{DBICDIST_DEBUG} set for more info'
  );

  postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_optdeps_pod

dbic_clonedir_gen_optdeps_pod :
\t@{[
  $mm_proto->oneliner("DBIx::Class::Optional::Dependencies->_gen_pod(q($ver), q($pod_dir/lib))", [qw/-Ilib -MDBIx::Class::Optional::Dependencies/])
]}

EOP
}


# generate the script/dbicadmin pod
{
  print "Regenerating script/dbicadmin.pod\n";

  # generating it in the root of $pod_dir
  # it will *not* be copied over due to not being listed at the top
  # of MANIFEST.SKIP - this is a *good* thing
  # we only want to ship a script/dbicadmin, with the POD appended
  # (see inject_dbicadmin_pod.pl), but still want to spellcheck and
  # whatnot the intermediate step
  my $pod_fn = "$pod_dir/dbicadmin.pod";

  # if the author doesn't have the prereqs, don't fail the initial "perl Makefile.pl" step
  my $great_success;
  {
    local @ARGV = ('--documentation-as-pod', $pod_fn);
    local $0 = 'dbicadmin';
    local *CORE::GLOBAL::exit = sub { $great_success++; die; };
    do 'script/dbicadmin';
  }
  if (!$great_success and ($@ || $!) ) {
    printf ("FAILED!!! Subsequent `make dist` will fail. %s\n",
      $ENV{DBICDIST_DEBUG}
        ? 'Full error: ' . ($@ || $!)
        : 'Re-run with $ENV{DBICDIST_DEBUG} set for more info'
    );
  }

  postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_dbicadmin_pod

dbic_clonedir_gen_dbicadmin_pod :
\t\$(ABSPERLRUN) -Ilib -- script/dbicadmin --documentation-as-pod @{[ $mm_proto->quote_literal($pod_fn) ]}

EOP
}


# generate the inherit pods only during distbuilding phase
# it is too slow to do at regular Makefile.PL
{
  postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_inherit_pods

dbic_clonedir_gen_inherit_pods :
\t\$(ABSPERLRUN) -Ilib maint/gen_pod_inherit

EOP
}


# generate the DBIx/Class.pod only during distdir
{
  my $dist_pod_fn = "$pod_dir/lib/DBIx/Class.pod";

  postamble <<"EOP";

clonedir_generate_files : dbic_distdir_gen_dbic_pod

dbic_distdir_gen_dbic_pod :

\tperldoc -u lib/DBIx/Class.pm > $dist_pod_fn
\t@{[ $mm_proto->oneliner(
  "s!^.*?this line is replaced with the author list.*! qq{List of the awesome contributors who made DBIC v$ver possible\\n\\n} . qx(\$^X -Ilib maint/gen_pod_authors)!me",
  [qw( -0777 -p -i.arghwin32 )]
) ]} $dist_pod_fn
\t\$(RM_F) $dist_pod_fn.arghwin32

create_distdir : dbic_distdir_defang_authors

# Remove the maintainer-only warning (be nice ;)
dbic_distdir_defang_authors :
\t@{[ $mm_proto->oneliner('s/ ^ \s* \# \s* \*\*\* .+ \n ( ^ \s* \# \s*? \n )? //xmg', [qw( -0777 -p -i.arghwin32 )] ) ]} \$(DISTVNAME)/AUTHORS
@{[ $crlf_fixup->( '$(DISTVNAME)/AUTHORS' ) ]}
\t\$(RM_F) \$(DISTVNAME)/AUTHORS.arghwin32

EOP
}


# on some OSes generated files may have an incorrect \n - fix it
# so that the xt tests pass on a fresh checkout (also shipping a
# dist with CRLFs is beyond obnoxious)
if ($^O eq 'MSWin32' or $^O eq 'cygwin') {
  {
    local $ENV{PERLIO} = 'unix';
    system( $^X, qw( -MExtUtils::Command -e dos2unix -- ), $pod_dir );
  }

  postamble <<"EOP";

clonedir_post_generate_files : pod_crlf_fixup

pod_crlf_fixup :
@{[ $crlf_fixup->($pod_dir) ]}

EOP
}

{
  postamble <<"EOP";

clonedir_post_generate_files : dbic_clonedir_copy_generated_pod

dbic_clonedir_copy_generated_pod :
\t\$(RM_F) $pod_dir.packlist
\t@{[
  $mm_proto->oneliner("install([ from_to => {q($pod_dir) => './', write => q($pod_dir.packlist)}, verbose => 0, uninstall_shadows => 0, skip => [] ])", ['-MExtUtils::Install'])
]}

EOP
}


# everything that came from $pod_dir, needs to be removed from the workdir
{
  postamble <<"EOP";

clonedir_cleanup_generated_files : dbic_clonedir_cleanup_generated_pod_copies

dbic_clonedir_cleanup_generated_pod_copies :
\t@{[ $mm_proto->oneliner('chomp && unlink || die', ['-n']) ]} $pod_dir.packlist
\t\$(RM_F) $pod_dir.packlist

EOP
}

# keep the Makefile.PL eval happy
1;
