package Functions::Feed::MyTest;

use strict;
use warnings;

sub cpc_calc
{
    my $factor = shift;
    return sprintf("%.2f", rand($factor) * 0.1);
}

1;
__END__
