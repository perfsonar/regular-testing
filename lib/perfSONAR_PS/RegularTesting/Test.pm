package perfSONAR_PS::RegularTesting::Test;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Digest::MD5;
use Data::UUID;

use Moose;

has 'id'                   => (is => 'rw', isa => 'Str', default => sub { Data::UUID->new()->create_str() });
has 'description'          => (is => 'rw', isa => 'Str');
has 'source'               => (is => 'rw', isa => 'Str');
has 'source_local'         => (is => 'rw', isa => 'Bool');
has 'destination'          => (is => 'rw', isa => 'Str');
has 'destination_local'    => (is => 'rw', isa => 'Bool');
has 'parameters'           => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Tests::Base');
has 'schedule'             => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Schedulers::Base');
has 'measurement_archives' => (is => 'rw', isa => 'ArrayRef[perfSONAR_PS::RegularTesting::MeasurementArchives::Base]');

my $logger = get_logger(__PACKAGE__);

sub init_test {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         config => 1,
                                      });
    my $config = $parameters->{config};

    return $self->parameters->init_test({
                                          source => $self->source,
                                          source_local => $self->source_local,
                                          destination => $self->destination,
                                          destination_local => $self->destination_local,
                                          schedule => $self->schedule,
                                          config => $config
                                       });
}

sub run_test {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         handle_results => 0,
                                      });
    my $handle_results = $parameters->{handle_results};

    return $self->parameters->run_test({
                                         source => $self->source,
                                         source_local => $self->source_local,
                                         destination => $self->destination,
                                         destination_local => $self->destination_local,
                                         schedule => $self->schedule,
                                         handle_results => $handle_results,
                                      });
}

sub stop_test {
    my ($self) = @_;

    return $self->parameters->stop_test();
}

sub handles_own_scheduling {
    my ($self) = @_;

    return $self->parameters->handles_own_scheduling();
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
