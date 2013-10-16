package perfSONAR_PS::RegularTesting::Schedulers::Base;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Moose;
use Class::MOP::Class;

my $logger = get_logger(__PACKAGE__);

sub check_configuration {
    my ($self) = @_;

    return;
}

sub type {
    die("Type needs to be overridden");
}

sub get_attributes {
    my $class = shift;

    my @ancestors = reverse $class->meta->linearized_isa;

    my %attrs = ();
    foreach my $class (@ancestors) {
        foreach my $attribute ( sort $class->meta->get_attribute_list ) {
            $attrs{$attribute->name} = 1 unless $attribute =~ /^_/;
        }
    }

    return keys %attrs;
}

1;
