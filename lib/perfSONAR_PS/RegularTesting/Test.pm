package perfSONAR_PS::RegularTesting::Test;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Digest::MD5;

use Moose;

has 'description' => (is => 'rw', isa => 'Str');
has 'source'      => (is => 'rw', isa => 'Str');
has 'destination' => (is => 'rw', isa => 'Str');
has 'parameters'  => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Tests::Base');
has 'schedule'    => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Schedulers::Base');

my $logger = get_logger(__PACKAGE__);

sub run_once {
    my ($self) = @_;

    return $self->parameters->run_once({ source => $self->source, destination => $self->destination });
}

sub calculate_next_run_time {
    my ($self) = @_;

    return $self->schedule->calculate_next_run_time();
}

sub nonce {
    my ($self) = @_;

    my $nonce = "";
    $nonce .= ( $self->source ? $self->source : "local" );
    $nonce .= "_";
    $nonce .= ( $self->destination ? $self->destination : "local" );
    $nonce .= "_".$self->parameters->type;

    my $parameters_md5 = Digest::MD5->new;

    foreach my $object ($self->parameters, $self->schedule) {
        my @attributes = get_attributes($object);
        foreach my $parameter (sort @attributes) {
            $parameters_md5->add($parameter);
            $parameters_md5->add($object->$parameter) if $object->$parameter;
        }
    }

    $nonce .= "_".$parameters_md5->hexdigest;

    return $nonce;
}

sub get_attributes {
    my $object = shift;

    my @ancestors = reverse $object->meta->linearized_isa;

    my %attrs = ();
    foreach my $object (@ancestors) {
        for my $attribute ( map { $object->meta->get_attribute($_) } sort $object->meta->get_attribute_list ) {
            $attrs{$attribute->name} = $attribute->type_constraint unless $attribute->name =~ /^_/;
        }
    }

    return keys %attrs;
}

1;
