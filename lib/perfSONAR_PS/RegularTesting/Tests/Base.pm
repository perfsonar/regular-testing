package perfSONAR_PS::RegularTesting::Tests::Base;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Moose;
use Class::MOP::Class;

my $logger = get_logger(__PACKAGE__);

has 'description' => (is => 'rw', isa => 'Str');

sub type {
    die("'type' needs to be overridden");
}

sub run_once {
    die("'run_once' needs to be overridden");
}

sub valid_target {
    die("'valid_target' needs to be overridden");
}

sub allows_bidirectional {
    return 0;
}

1;
