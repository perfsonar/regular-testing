package perfSONAR_PS::RegularTesting::Master::TesterChild;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Time::HiRes;
use File::Spec;
#use File::Path qw(make_path);
use File::Path;
use POSIX;
use JSON;

use Moose;

extends 'perfSONAR_PS::RegularTesting::Master::BaseChild';

has 'test'         => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Test');

has 'starting'     => (is => 'rw', isa => 'Bool');

my $logger = get_logger(__PACKAGE__);

sub start_test {
    my ($self) = @_;

    return unless $self->pid;

    kill('USR1', $self->pid);
}

sub stop_test {
    my ($self) = @_;

    return unless $self->pid;

    kill('USR2', $self->pid);
}

override 'child_initialize_signals' => sub {
    my ($self) = @_;

    $SIG{USR1} = sub {
        $self->handle_start_test();
    };

    $SIG{USR2} = sub {
        $self->handle_stop_test();
    };

    return super();
};

sub handle_start_test {
    my ($self) = @_;

    $self->starting(1);

    return;
}

override 'child_main_loop' => sub {
    my ($self) = @_;

    while (1) {
        # Wait to get a signal from the master
        while (not $self->starting) {
            sleep(-1);
        }

        $self->starting(0);

        $logger->debug("Running test: ".$self->test->description);

        my $results;
        eval {
            $results = $self->test->run_once();
        };
        if ($@) {
            my $error = $@;
            $logger->error("Problem running test: ".$self->test->description.": ".$error);
            #$self->error($@);
        };

        eval {
            $self->save_results(results => $results);
        };
        if ($@) {
            my $error = $@;
            $logger->error("Problem saving test results: ".$self->test->description.": ".$error);
            #$self->error($@);
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
        $logger->debug("Enqueueing job to: ".$measurement_archive->queue_directory);

        my $queue = IPC::DirQueue->new({ dir => $measurement_archive->queue_directory });
        unless ($queue->enqueue_string($json)) {
            $logger->error("Problem saving test results to measurement archive");
        }
    }

    return;
}

1;
