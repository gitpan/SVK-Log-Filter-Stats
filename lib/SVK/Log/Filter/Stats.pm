package SVK::Log::Filter::Stats;

use strict;
use warnings;

use SVK::Log::Filter;
use List::Util qw( max min minstr maxstr );
use Time::Local;

our $VERSION = '0.0.1';

sub setup {
    my ($self, $stash) = @_[SELF, STASH];

    $stash->{stats_commits} = 0;
    $stash->{stats_committers} = {};
    $stash->{stats_files} = {};

    # hacks!
    $stash->{stats_newest_commit} = '';
    $stash->{stats_oldest_commit}   = '9999-99-99';
}

sub revision {
    my ($self, $props, $changed_paths, $stash) = @_[SELF, PROPS, PATHS, STASH];

    my $date   = $props->{'svn:date'}   || q{};
    my $author = $props->{'svn:author'} || 'no author';

    # track the commit dates (usually from newest to oldest)
    $stash->{stats_newest_commit} = maxstr( $stash->{stats_newest_commit}, $date );
    $stash->{stats_oldest_commit} = minstr( $stash->{stats_oldest_commit}, $date );

    $stash->{stats_commits}++;
    $stash->{stats_committers}{$author}++;

    for my $changed_path ( $changed_paths->paths() ) {
        my $path = $changed_path->path();
        $stash->{stats_files}{$path}++;
    }

    return;
}

sub footer {
    my ($self, $stash) = @_[SELF, STASH];

    my $quiet   = $stash->{quiet};
    my $verbose = $stash->{verbose};

    $self->newest_commit($stash);
    $self->oldest_commit($stash);
    print "Commits: ", $stash->{stats_commits}, "\n";

    my $days = $self->days($stash);
    $self->commits_per_day($stash, $days);


    my $author_count = $verbose ? 999_999 : 5;
    $self->author_details($stash, $author_count) if !$quiet;
    $self->file_details($stash, 5) if $verbose;

    if ($verbose) {
        print "Concentration:\n";
        $self->concentration_ratio($stash);
        $self->herfindahl($stash);
    }

    return;
}


sub newest_commit {
    my ($self, $stash) = @_;
    my $newest = substr($stash->{stats_newest_commit}, 0, 10);
    print "Newest commit : $newest\n";
}

sub oldest_commit {
    my ($self, $stash) = @_;
    my $oldest = substr($stash->{stats_oldest_commit}, 0, 10);
    print "Oldest commit : $oldest\n";
}

sub days {
    my ($self, $stash) = @_;
    my $young = _date_into_time( $stash->{stats_newest_commit} );
    my $old = _date_into_time( $stash->{stats_oldest_commit} );

    my $delta = $young - $old;
    my $days = int($delta/86400);
    print "Days: $days\n";
    return $days;
}

sub _date_into_time {
    my ($date) = @_;

    my ($y, $m, $d, $h, $min, $s, $ms) = split /[-T:.]/, $date;
    $m--;
    $y -= 1900;
    return timegm($s,$min,$h,$d,$m,$y);
}

sub commits_per_day {
    my ($self, $stash, $days) = @_;

    return if $days < 1;
    return if $stash->{stats_commits} < 1;

    my $c_per_day = $stash->{stats_commits} / $days;

    if ( $c_per_day > 1 ) {
        printf "Commits per day : %.1f\n", $c_per_day;
    }
    else {
        printf "Days per commit : %.1f\n", (1 / $c_per_day);
    }
}

sub author_details {
    my ($self, $stash, $count) = @_;
    $count ||= 5;

    # sort the committer list by commits
    my @committers;
    while ( my ($author, $commits) = each %{ $stash->{stats_committers} } ) {
        push @committers, [ $author, $commits ];
    }
    @committers = sort { $b->[1] <=> $a->[1] } @committers;

    print  "Committer count: ", (scalar @committers), "\n";

    # trim the list of committers
    my $count_index = min( $count-1, $#committers );
    @committers = @committers[ 0 .. $count_index ];

    # display the top committers
    my $longest = max map { length $_->[0] } @committers;
    print  "Most active committers:\n";
    foreach (@committers) {
        my ( $author, $count ) = @$_;
        $author .= ' 'x( $longest - length($author) );
        print "  - $author ($count)\n";
    }
}

sub file_details {
    my ($self, $stash, $count) = @_;
    $count ||= 5;

    # sort the file list by modifications
    my @files;
    while ( my ($path, $commits) = each %{ $stash->{stats_files} } ) {
        push @files, [ $path, $commits ];
    }
    @files = sort { $b->[1] <=> $a->[1] } @files;

    print "Count of modified paths: ", (scalar @files), "\n";

    # trim the list of files
    my $count_index = min( $count-1, $#files );
    @files = @files[ 0 .. $count_index ];

    # display the file details
    my $longest = max map { length $_->[0] } @files;
    print  "Most modified paths:\n";
    foreach (@files) {
        my ( $file, $count ) = @$_;
        $file .= ' 'x( $longest - length($file) );
        print "  - $file ($count)\n";
    }
}

sub concentration_ratio {
    my ($self, $stash) = @_;

    my $commit_count = $stash->{stats_commits};
    return if $commit_count < 1;

    my @committers;
    for my $commits ( values %{ $stash->{stats_committers} } ) {
        push @committers, $commits;
    }
    return if @committers < 4;
    @committers = sort { $b <=> $a } @committers;
    @committers = @committers[ 0 .. 3 ];  # get the top 4

    # find the total commits performed by the top 4
    my $commits_by_top = 0;
    for ( @committers ) {
        $commits_by_top += $_;
    }

    printf "  Concentration ratio : %.2f\n", ($commits_by_top / $commit_count);
}

sub herfindahl {
    my ($self, $stash) = @_;

    my $commit_count = $stash->{stats_commits};
    return if $commit_count < 1;

    my @committers;
    for my $commits ( values %{ $stash->{stats_committers} } ) {
        push @committers, $commits;
    }

    my $cumulative_herfindahl = 0;
    for ( @committers ) {
        $cumulative_herfindahl += ( $_ / $commit_count * 100 ) ** 2;
    }

    printf "  Herfindahl index : \%d\n", $cumulative_herfindahl;
    printf "  Normalized Herfindahl index : %.2f\n",
        ( $cumulative_herfindahl / 10_000 );
    printf "  Equivalent committers : %.1f\n",
        ( 10_000 / $cumulative_herfindahl );
}

1;

__END__

=head1 NAME

SVK::Log::Filter::Stats - display statistics for a repository or working copy

=head2 SYNOPSIS

    > svk log --output stats //mirror/svk/trunk
    Newest commit : 2006-05-13
    Oldest commit : 2004-07-31
    Commits: 1310
    Days: 651
    Commits per day : 2.0
    Committer count: 13
    Most active committers:
      - clkao    (911)
      - autrijus (244)
      - gugod    (42)
      - matthewd (26)
      - mb       (22)

    > svk log --output stats --verbose --limit 100 //mirror/svk/trunk
    Newest commit : 2006-05-13
    Oldest commit : 2005-11-04
    Commits: 100
    Days: 190
    Days per commit : 1.9
    Committer count: 8
    Most active committers:
      - clkao    (69)
      - stig     (8)
      - mndrix   (7)
      - mb       (6)
      - autrijus (3)
      - nnunley  (3)
      - jesse    (3)
      - gugod    (1)
    Count of modified paths: 138
    Most modified paths:
      - /mirror/svk/trunk                    (20)
      - /mirror/svk/trunk/lib/SVK/XD.pm      (18)
      - /mirror/svk/trunk/lib/SVK/Merge.pm   (16)
      - /mirror/svk/trunk/lib/SVK/Path.pm    (13)
      - /mirror/svk/trunk/lib/SVK/Command.pm (13)
    Concentration:
      Concentration ratio : 0.90
      Herfindahl index : 4938
      Normalized Herfindahl index : 0.49
      Equivalent committers : 2.0

=head1 DESCRIPTION

The Stats filter is an output filter which displays statistics about the
revisions it sees.  The specific statistics are described in the
L</STATISTICS> section.  Two arguments to the log command modify the
statistics output format.

=head2 quiet

Providing this command-line option to the log command supresses the
L</Most active committers> and L</Committer count> statistics.

=head2 verbose

Providing this command-line option to the log command causes the following
changes:

=over

=item *

Display all authors in the L</Most active committers> statistic

=item *

Display the L</Count of modified files> and L</Most modified files> statistics

=item *

Display the concentration statistics: L</Concentration ratio>,
L</Herfindahl index>, L</Normalized Herfindahl index>.

=back

=head1 STATISTICS

=head2 Newest commit

The date of the most recent commit that the filter saw.  The date is in the
UTC timezone.

=head2 Oldest commit

The date of the oldest commit that the filter saw. The date is in the UTC
timezone.

=head2 Commits

The number of commits that the filter saw.

=head2 Days

The number of days between L</Newest commit> and L</Oldest commit>.  A day is
defined as 86,400 seconds.

=head2 Commits per day

The number of commits per day (on average).  This is the value of L</Commits>
divided by the value of L</Days>.  If the value would be less than 1,
L</Days per commit> is displayed instead.

=head2 Days per commit

The number of days between each commit (on average).  This is the value of
L</Days> divided by the value of L</Commits>.  If the value would be less than
1, L</Commits per day> is displayed instead.

=head2 Committer count

The number of different revision authors seen by the filter.  This statistic
is suppressed with the C<--quiet> option.

=head2 Most active committers

Provides the name and commit count for the top 5 committers seen by the
filter.  If the C<--verbose> option is given to the log command, all authors
are shown.  The authors are listed in order of decreasing commit count.  This
statistic is suppressed with the C<--quiet> option.

=head2 Count of modified paths

Shows the number of files and directories that were modified by revisions that
the filter saw.  This statistic is only shown if the C<--verbose> option was
given.

=head2 Most modified paths

Shows the top 5 most-modified files and directories within the revisions seen
by the filter.  The path and the number of commits modifying the path are
included in the output.

=head2 Concentration ratio

Concentration metrics are used within economics to indicate the relative size
of firms within a particular industry.  The metrics are generally based on the
number of firms and the market share of each firm.  Small numbers indicate
that there are many firms, each holding a small market share.  Large numbers
indicate that there are few firms holding a majority of the market.

Applying concentration metrics to version control is perhaps dubious, but can
provide a sense of the culture behind the project under revision control.
This filter views each committer as a "firm" and each commit as a part of the
market.  A project in which a single committer made all the revisions would
have a large concentration metric.  A project with many committers each making
numerous commits would have a small concentration metric.

The concentration ratio is a particular concentration metric.  This filter
uses the 4-firm concentration ratio which is the percentage of commits
performed by the top four committers.  The value ranges from 0 (low
concentration) to 1 (high concentration).  See
L<http://en.wikipedia.org/wiki/Concentration_ratio> for more information.

=head2 Herfindahl index

The Herfindahl index (aka Herfindahl-Hirschman index) is a concentration
metric which gives more weight to the size of large firms.  The details of the
calculation are available from
L<http://www.usdoj.gov/atr/public/testimony/hhi.htm>.  The value of the
Herfindahl index ranges from 0 to 10,000.  In economics, a value of 1800 or
higher is considered to be "concentrated."

=head2 Normalized Herfindahl index

The Herfindahl index divided by 10,000.  This makes the number vary between 0
and 1.

=head2 Equivalent committers

The inverse of the L</Normalized Herfindahl index>.  This is the number of
committers, equally distributed, that would be needed to approximate the
current "project culture".  For instance if a project has an "Equivalent
committers" value of 10, the distribution of commits among committers is the
same as if there were 10 committers with the commits evenly distributed among
them.

=head1 STASH/PROPERTY MODIFICATIONS

Stats leaves all properties intact and only modifies the stash under the
"stats_" namespace.

=head1 AUTHORS

Michael Hendricks E<lt>michael@palmcluster.orgE<gt>

=head1 COPYRIGHT

Copyright 2006 by Michael Hendricks E<lt>michael@palmcluster.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
