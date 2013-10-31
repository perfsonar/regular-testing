package perfSONAR_PS::RegularTesting::Master::SelfScheduledTestChild;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Time::HiRes;
use POSIX;
use JSON;

use Moose;

extends 'perfSONAR_PS::RegularTesting::Master::BaseChild';

has 'test'         => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Test');

has 'ma_queues'    => (is => 'rw', isa => 'HashRef', default => sub { {} } );

my $logger = get_logger(__PACKAGE__);

override 'child_main_loop' => sub {
    my ($self) = @_;

    while (1) {
        $logger->debug("Running test: ".$self->test->description);

        my $results;
        eval {
            $self->test->run_test(
                handle_results => sub {
                    my $parameters = validate( @_, { results => 1 });
                    my $results = $parameters->{results};
                    $self->save_results(results => $results);
                }
            );
        };
        if ($@) {
            my $error = $@;
            $logger->error("Problem with test: ".$self->test->description.": ".$error);
        };
    }

    return;
};

sub save_results {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { results => 1 });
    my $results = $parameters->{results};

    my $json = JSON->new->pretty->encode($results->unparse);

    foreach my $measurement_archive (@{ $self->test->measurement_archives }) {
        if ($measurement_archive->accepts_results({ results => $results })) {
            $logger->debug("Enqueueing job to: ".$measurement_archive->queue_directory);

            my $queue = $self->ma_queues->{$measurement_archive->id};
            unless ($queue) {
                $logger->error("No queue available for measurement archive");
            }
            elsif ($queue->enqueue_string($json)) {
                $logger->error("Problem saving test results to measurement archive");
            }
        }
    }

    return;
}

1;
