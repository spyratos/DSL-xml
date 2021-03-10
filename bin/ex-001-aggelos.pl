use Adzuna::DSL::PF;


my $conf_path = '../samples/ex-001-aggelos.yaml';

my $yaml_obj = Adzuna::DSL::PF->load_yaml($conf_path);

my $pfd = Adzuna::DSL::PF->new($yaml_obj); # Partner-feed descriptor

$pfd->process_conf;

print $pfd->{'ad_xml'};
