package Adzuna::DSL::PF;

# TODO: rework on parsing order
#   - prefer ensuring order
#   - avoid "hash-random" order

use strict;
use warnings;

use YAML::XS qw();
use Const::Fast;
use XML::Writer;
use Module::Load::Conditional qw/ can_load /;

# use Exceptions;
use Carp qw(croak);

const my %E_STRUCTURE_XML_WRITER_DEFAULT_OPTIONS => (
    DATA_MODE => 1,
    ENCODING => 'utf-8',
    DATA_INDENT => 2,
);

const my $DB_PATH => '../data/ads.yaml'; # relative to sample Perl script.


sub exception
{
    croak(@_);
}

sub load_yaml
{
    my ($class, $path) = @_;

    my $yaml_obj = YAML::XS::LoadFile($path);

    return $yaml_obj;
}



sub new
{
    my ($class, $yaml_obj) = @_;

    my $obj = {
        conf => $yaml_obj,
        parsed_keys => {},
        ad_xml => '',
    };

    return bless $obj, __PACKAGE__;
}


sub _validate_state
{
    # TODO: nyi

    # TODO: can we load the module?
    return 1;
}


sub _begin_nesting
{
    my ($self) = @_;

    # TODO: check has begun nesting

    my $writer = $self->{'writer'};
    my $nesting = $self->{'nesting'};

    foreach ( @$nesting )
    {
        $writer->startTag($_);
    }
}



sub _end_nesting
{
    my ($self) = @_;

    # TODO: check has ended nesting

    my $writer = $self->{'writer'};
    my $nesting = $self->{'nesting'};

    foreach ( reverse(@$nesting) )
    {
        $writer->endTag($_);
    }
}



sub _process_ad_attributes
{
    my ($self, $ad, $tags) = @_;
    # my $tags = $self->{'tags'};

    while ( my ($attr, $value) = each(%$tags) )
    {
        my $value_type = ref($value);

        # if undefined value
        if ( ! defined($value) )
        {
            exception('TODO'); # TODO
        }
        # if scalar => derived = value
        elsif ( ! $value_type )
        {
            $self->_process_simple_ad_attribute($ad, $attr, $ad->{$value});
        }
        # if hash
        elsif ( $value_type eq 'HASH' )
        {

            if ( grep { $_ =~ /^_/ } keys(%$value) )
            {
                # options
                $self->_process_ad_attribute_options($ad, $attr, $value)
            }
            else
            {
                # composite element
                $self->_process_composite_ad_attribute($ad, $attr, $value);
            }
        }
        else
        {
            exception('TODO'); # TODO
        }
    }

}



sub _process_ad_attribute_options
{
    my ($self, $ad, $attr, $value) = @_;
    my $module = $self->{'module'};

    my %options = %$value;

    my $cdata = 0;
    my $derived_value;

    foreach my $opt_name (keys %options)
    {
        if ($opt_name eq '_cdata')
        {
            $cdata = 1;
        }
        elsif ($opt_name eq '_regex')
        {
            while ( my ($k, $v) = each( %{$options{$opt_name}} ) )
            {
                my $regex = eval("qr$v");
                my $tested_value = $ad->{$k};

                if ($tested_value =~ $regex)
                {
                    $derived_value = $1;
                }
                else
                {
                    exception("TODO _regex v: $v test: $tested_value");
                }
            }
        }
        elsif ($opt_name eq '_function')
        {
            while ( my ($k, $v) = each( %{$options{$opt_name}} ) )
            {
                my $method_name = join '::', $module, $k; # build method name
                no strict;
                $derived_value = $method_name->(@$v);
                use strict;
            }
        }
        elsif ($opt_name eq "_field")
        {
            $derived_value = $ad->{$options{$opt_name}};
        }
        elsif ($opt_name eq "_value")
        {
            $derived_value = $options{$opt_name};
        }
        else
        {
            exception("TODO wrong option");
        }
    }

    return $self->_process_simple_ad_attribute($ad, $attr, $derived_value, $cdata);
}



sub _process_composite_ad_attribute
{
    my ($self, $ad, $attr, $value) = @_;
    my $writer = $self->{'writer'};

    $writer->startTag($attr);
    my $result = $self->_process_ad_attributes($ad, $value);
    $writer->endTag($attr);

    return $result;
}



sub _process_simple_ad_attribute
{
    my ($self, $ad, $attr, $value, $cdata) = @_;
    $cdata //= 0;
    my $writer = $self->{'writer'};

    if ($cdata)
    {
        $writer->cdataElement( $attr => $value );
    }
    else
    {
        $writer->dataElement( $attr => $value );
    }

    return $self;
}



sub _process_ad
{
    my ($self, $ad) = @_;
    my $writer = $self->{'writer'};
    my $tags = $self->{'tags'};
    my $module = $self->{'module'};
    my $max_ads = $self->{'maxads'};
    my $unprocessed_ads = $self->{'unprocessed_ads'};

    # TODO: report illegal state if conf not parsed

    # load partner feed's custom module
    can_load( modules => { $module => undef } ) or exception("Cannot load module '$module'");

    # TODO: run for each ad attribute

    # first goes max_ads
    if( defined($unprocessed_ads) && $unprocessed_ads == 0 )
    {
        return $self;
    }

    # then filtering
    while ( my ($key, $value) = each (%{$self->{'inclusions'}}))
    {
        my $regex = eval("qr$value");

        if ($ad->{$key} !~ $regex)
        {
            return $self;
        }
    }
    while ( my ($key, $value) = each (%{$self->{'exclusions'}}))
    {
        my $regex = eval("qr$value");

        if ($ad->{$key} =~ $regex)
        {
            return $self;
        }
    }

    # write attributes in file
    $writer->startTag($self->{'job_tag'});
    $self->_process_ad_attributes($ad, $self->{'tags'});
    $writer->endTag($self->{'job_tag'});

    # reduce the limit counter if any
    if (defined($unprocessed_ads))
    {
        $self->{'unprocessed_ads'} -= 1;
    }

    return $self;
}



sub process_conf
{
    my ($self) = @_;

    # step 1: conf preprocessing -> complete obj
    # TODO: convert this step to helper method
    my %conf = %{$self->{conf}};

    while (my ($key, $value) = each (%conf))
    {
        if (! $self->{'parsed_keys'}{$key})
        {
            my $method = "e_$key";
            $self->$method($value);
            $self->{'parsed_keys'}{$key} = 1;
        }
    }

    # step 2: validate object's integrity
    $self->_validate_state;

    # step 2.5: fetch ads; apply filtering; !keep ids only!
    # $self->fetch_ads;

    # step 3: begin nesting
    $self->_begin_nesting;

    # step 3.5: for DEMO purposes, load ads from YAML
    my $ads_yaml = $self->load_yaml($DB_PATH);

    # step 4: populate document with ads
    my $ads = $ads_yaml->{'jobs'};
    foreach (@$ads)
    {
        $self->_process_ad($_);
    }

    # step 5: end nesting
    $self->_end_nesting;

    return $self;
}



sub e_structure
{
    my ($self, $value) = @_;

    my $value_type = ref($value);
    my $options;

    if ($value_type eq 'HASH')
    {
        $options = $value->{'_options'};
        $value = $value->{'_value'};
    }

    # TODO if not HASH nor scalar throw something!

    if (uc($value) eq 'XML')
    {
        $self->{'writer'} = XML::Writer->new(
            # OUTPUT => \$ad_xml,
            OUTPUT => \$self->{ad_xml}, # uncle Angelos thanks
            %E_STRUCTURE_XML_WRITER_DEFAULT_OPTIONS,
            %$options,
        );
    }
    else
    {
        exception("Illegal value for structure: $value");
    }
    return $self;
}


# TODO: combine and refactor _ensure_* methods
sub _ensure_nesting
{
    my ($self) = @_;

    my $key = 'nesting';
    my $result;

    if ( $self->{'parsed_keys'}{$key} )
    {
        if ($self->{$key})
        {
            $result = $self->{$key};
        }
        else
        {
            exception("Illegal state for $key; flagged parsed without value");
        }
    }
    else
    {
        my $value = $self->{'conf'}{$key};
        my $method_name = "e_$key";
        $self->$method_name($value);
        $self->{'parsed_keys'}{$key} = 1; # prevent re-parsing the same key
    }
    return $result;
}



sub _ensure_tags
{
    my ($self) = @_;

    my $key = 'tags';
    my $result;

    if ( $self->{'parsed_keys'}{$key} )
    {
        if ($self->{$key})
        {
            $result = $self->{$key};
        }
        else
        {
            exception("Illegal state for $key; flagged parsed without value");
        }
    }
    return $result;
}

# TODO: take care of empty or trash nesting values
sub e_nesting
{
    my ($self, $value) = @_;

    my @parts = split('/', $value);

    my $job_tag = pop @parts;
    my @nesting = @parts;

    $self->{'nesting'} = \@nesting;
    $self->{'job_tag'} = $job_tag;

    return $self;
}



sub e_tags
{
    my ($self, $value) = @_;
    # TODO: if $value no HASH? What? E?

    # just store mapping
    $self->{'tags'} = $value;

    return $self;
}



sub e_maxads
{
    my ($self, $value) = @_;
    $self->{'maxads'} = $value;
    $self->{'unprocessed_ads'} = $self->{'maxads'};
    return $self;
}



sub e_filters
{
    my ($self, $value) = @_;

    # include filters
    $self->{'inclusions'} =
        ( $value && defined($value->{'include'}) ) ?
        $value->{'include'} : {};

    # exclude filters
    $self->{'exclusions'} =
        ( $value && defined($value->{'exclude'}) ) ?
        $value->{'exclude'} : {};

    return $self;
}


sub e_type
{
    my ($self, $value) = @_;

    # my $nesting = $self->_ensure_nesting;
    # my $tags = $self->_ensure_tags;

    $self->{'type'} = $value;

    return $self;
}



sub e_module
{
    my ($self, $value) = @_;

    $self->{'module'} = $value;

    return $self;
}



# sub e_type_v_standard


# sub AUTOLOAD
# {
#     our $AUTOLOAD;
#     return $AUTOLOAD;
# }


1;
__END__
