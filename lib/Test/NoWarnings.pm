package Test::NoWarnings;

use 5.006;
use strict;
use warnings;
use Carp                      ();
use Exporter                  ();
use Test::Builder             ();
use Test::NoWarnings::Warning ();

our ( $VERSION, @EXPORT_OK, @ISA, $do_end_test );
BEGIN {
    $VERSION   = '1.06';
    @ISA       = 'Exporter';
    @EXPORT_OK = qw(
        clear_warnings
        had_no_warnings
        warnings
    );

    # Do we add the warning test at the end?
    $do_end_test = 0;
}

my $TEST     = Test::Builder->new;
my $PID      = $$;
my @WARNINGS = ();
my $EARLY    = 0;

$SIG{__WARN__} = make_catcher(\@WARNINGS);

sub import {
    $do_end_test = 1;
    if ( grep { $_ eq ':early' } @_ ) {
        @_ = grep { $_ ne ':early' } @_;
        $EARLY = 1;
    }
    goto &Exporter::import;
}

# the END block must be after the "use Test::Builder" to make sure it runs
# before Test::Builder's end block
# only run the test if there have been other tests
END {
    had_no_warnings() if $do_end_test;
}

sub make_warning {
    local $SIG{__WARN__};

    my $msg     = shift;
    my $warning = Test::NoWarnings::Warning->new;

    $warning->setMessage($msg);
    $warning->fillTest($TEST);
    $warning->fillTrace(__PACKAGE__);

    $Carp::Internal{__PACKAGE__.""}++;
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    $warning->fillCarp($msg);
    $Carp::Internal{__PACKAGE__.""}--;

    return $warning;
}

# this make a subroutine which can be used in $SIG{__WARN__}
# it takes one argument, a ref to an array
# it will push the details of the warning onto the end of the array.
sub make_catcher {
    my $array = shift;

    return sub {
        my $msg = shift;

        # Generate the warning
        $Carp::Internal{__PACKAGE__.""}++;
        push(@$array, make_warning($msg));
        $Carp::Internal{__PACKAGE__.""}--;

        # Show the diag early rather than at the end
        if ( $EARLY ) {
            $TEST->diag( $array->[-1]->toString );
        }

        return $msg;
    };
}

sub had_no_warnings {
    return 0 if $$ != $PID;

    $do_end_test = 0; # for use with done_testing

    local $SIG{__WARN__};
    my $name = shift || "no warnings";

    my $ok;
    my $diag;
    if ( @WARNINGS == 0 ) {
        $ok = 1;
    } else {
        $ok = 0;
        $diag = "There were " . scalar(@WARNINGS) . " warning(s)\n";
        unless ( $EARLY ) {
            $diag .= join "----------\n", map { $_->toString } @WARNINGS;
        }
    }

    $TEST->ok($ok, $name) || $TEST->diag($diag);

    return $ok;
}

sub clear_warnings {
    local $SIG{__WARN__};
    @WARNINGS = ();
}

sub warnings {
    local $SIG{__WARN__};
    return @WARNINGS;
}

sub builder {
    local $SIG{__WARN__};
    if ( @_ ) {
        $TEST = shift;
    }
    return $TEST;
}

1;

__END__

=pod

=head1 NAME

Test::NoWarnings - Make sure you didn't emit any warnings while testing

=head1 SYNOPSIS

For scripts that have no plan

  use Test::More 'no_plan';
  use Test::NoWarnings;

that's it, you don't need to do anything else

For scripts that look like

  use Test::More tests => x;

change to

  use Test::More tests => x + 1;
  use Test::NoWarnings;

For scripts that use L<done_testing|Test::More/done_testing>, use:

  use Test::More;
  use Test::NoWarnings 'had_no_warnings';

  ... # your actual tests

  had_no_warnings;
  done_testing;

=head1 DESCRIPTION

In general, your tests shouldn't produce warnings. This modules causes any
warnings to be captured and stored. It automatically adds an extra test that
will run when your script ends to check that there were no warnings. If
there were any warnings, the test will give a "not ok" and diagnostics of
where, when and what the warning was, including a stack trace of what was
going on when the it occurred.

If some of your tests B<are supposed to> produce warnings then you should be
capturing and checking them with L<Test::Warn>, that way L<Test::NoWarnings>
will not see them and so not complain.

The test is run by an C<END> block in Test::NoWarnings. It will not be run
when any forked children exit.

=head1 USAGE

Simply by using the module, you automatically get an extra test at the end
of your script that checks that no warnings were emitted. So just stick

  use Test::NoWarnings;

at the top of your script and continue as normal.

If you want more control you can invoke the test manually at any time with
C<had_no_warnings>.

The warnings your test has generated so far are stored in an array. You can
look inside and clear this whenever you want with C<warnings()> and
C<clear_warnings>, however, if you are doing this sort of thing then you
probably want to use L<Test::Warn> in combination with L<Test::NoWarnings>.

If you have a test script written using L<done_testing|Test::More/done_testing>
and no test plan, you have to call L</had_no_warnings> before you call
L<done_testing|Test::More/done_testing>.

=head2 use vs require

You will almost always want to do

  use Test::NoWarnings;

If you do a C<require> rather than a C<use>, then there will be no automatic
test at the end of your script.

=head2 Output

If warning is captured during your test then the details will output as part
of the diagnostics. You will get:

=over 2

=item *

the number and name of the test that was executed just before the warning
(if no test had been executed these will be 0 and '')

=item *

the message passed to C<warn>,

=item *

a full dump of the stack when warn was called, courtesy of the C<Carp>
module

=back

By default, all warning messages will be emitted in one block at the end of
your test script.

=head2 The :early pragma

One common complaint from people using Test::NoWarnings is that all of the
warnings are emitted in one go at the end. While this is the safest and
most correct time to emit these diagnostics, it can make debugging these
warnings difficult.

As of Test::NoWarnings 1.04 you can provide an experimental C<:early> pragma
when loading the module to force warnings to be thrown via diag at the time
that they actually occur.

  use Test::NoWarnings ':early';

As this will cause the diag to be emitted against the previous test and not
the one in which the warning actually occurred it is recommended that the
pragma be turned on only for debugging and left off when not needed.

=head1 FUNCTIONS

=head2 had_no_warnings

This checks that there have been warnings emitted by your test scripts.
Usually you will not call this explicitly as it is called automatically when
your script finishes.

=head2 clear_warnings

This will clear the array of warnings that have been captured. If the array
is empty then a call to C<had_no_warnings()> will produce a pass result.

=head2 warnings

This will return the array of warnings captured so far. Each element of this
array is an object containing information about the warning. The following
methods are available on these object.

=over 2

=item *

$warn->getMessage

Get the message that would been printed by the warning.

=item *

$warn->getCarp

Get a stack trace of what was going on when the warning happened, this stack
trace is just a string generated by the L<Carp> module.

=item *

$warn->getTrace

Get a stack trace object generated by the L<Devel::StackTrace> module. This
will return undef if L<Devel::StackTrace> is not installed.

=item *

$warn->getTest

Get the number of the test that executed before the warning was emitted.

=item *

$warn->getTestName

Get the name of the test that executed before the warning was emitted.

=back

=head1 PITFALLS

When counting your tests for the plan, don't forget to include the test that
runs automatically when your script ends.

Checking for warnings is done using L<< C<$SIG{__WARN__}>|perlvar/%SIG >>.
If other modules use this hook, it can interfere with this module's operation.
For example, using the L<Carp::Always> module will cause this module to always
report no warnings.

Testing via this module is possible when using L<Test::More> or other L<Test::Builder>
or L<Test2> based testing modules. e.g. L<Test> doesn't work.

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<https://rt.cpan.org/Ticket/Create.html?Queue=Test-NoWarnings>

For other issues, contact the author.

=head1 HISTORY

This was previously known as L<Test::Warn::None>

=head1 SEE ALSO

L<Test::Builder>, L<Test::Warn>

=head1 AUTHORS

Fergal Daly <fergal@esatclear.ie>

Adam Kennedy <adamk@cpan.org>

=head1 COPYRIGHT

Copyright 2003 - 2007 Fergal Daly.

Some parts copyright 2010 - 2011 Adam Kennedy.

This program is free software and comes with no warranty. It is distributed
under the LGPL license

See the file F<LICENSE> included in this distribution or
F<http://www.fsf.org/licenses/licenses.html>.

=cut
