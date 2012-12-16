use File::Path();
use File::Glob();

# leftovers in old checkouts
unlink 'lib/DBIx/Class/Optional/Dependencies.pod'
  if -f 'lib/DBIx/Class/Optional/Dependencies.pod';
File::Path::rmtree( File::Glob::bsd_glob('.generated_pod'), { verbose => 0 } )
  if -d '.generated_pod';

my $pod_dir = 'maint/.Generated_Pod';
my $ver = Meta->version;

# cleanup the generated pod dir (again - kill leftovers from old checkouts)
if (-d $pod_dir) {
  File::Path::rmtree( File::Glob::bsd_glob("$pod_dir/*"), { verbose => 0 } );
}
else {
  mkdir $pod_dir or die "Unable to create $pod_dir: $!";
}

# generate the OptDeps pod both in the clone-dir and during the makefile distdir
{
  print "Regenerating Optional/Dependencies.pod\n";
  require DBIx::Class::Optional::Dependencies;
  DBIx::Class::Optional::Dependencies->_gen_pod ($ver, "$pod_dir/lib");

  postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_optdeps_pod

dbic_clonedir_gen_optdeps_pod :
\t@{[
  $mm_proto->oneliner("DBIx::Class::Optional::Dependencies->_gen_pod(q($ver), q($pod_dir/lib))", [qw/-Ilib -MDBIx::Class::Optional::Dependencies/])
]}

EOP
}


# generate the inherit pods both in the clone-dir and during the makefile distdir
{
  print "Regenerating project documentation to include inherited methods\n";

  # if the author doesn't have them, don't fail the initial "perl Makefile.pl" step
  do "maint/gen_pod_inherit" or print "\n!!! FAILED: $@\n";

  postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_inherit_pods

dbic_clonedir_gen_inherit_pods :
\t\$(ABSPERLRUN) -Ilib maint/gen_pod_inherit

EOP
}


# copy the contents of $pod_dir over to the workdir
# (yes, overwriting is fine, though nothing should reside there)
{
  postamble <<"EOP";

clonedir_post_generate_files : dbic_clonedir_copy_generated_pod

dbic_clonedir_copy_generated_pod :
\t\$(RM_F) $pod_dir.packlist
\t@{[
  $mm_proto->oneliner("install([ from_to => {q($pod_dir) => File::Spec->curdir(), write => q($pod_dir.packlist)}, verbose => 0, uninstall_shadows => 0, skip => [] ])", ['-MExtUtils::Install'])
]}
EOP
}


# everything that came from $pod_dir, needs to be removed from the workdir
{
  postamble <<"EOP";

clonedir_cleanup_generated_files : dbic_clonedir_cleanup_generated_pod_copies

dbic_clonedir_cleanup_generated_pod_copies :
\t@{[
  $mm_proto->oneliner("uninstall(q($pod_dir.packlist))", ['-MExtUtils::Install'])
]}

EOP
}

# keep the Makefile.PL eval happy
1;
