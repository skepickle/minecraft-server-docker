#!/usr/bin/perl -w
use strict;
use warnings;
use POSIX ":sys_wait_h";
use IPC::SysV qw(IPC_STAT IPC_PRIVATE IPC_CREAT IPC_EXCL S_IRUSR S_IWUSR IPC_RMID);
use Term::ReadLine;
use Term::ReadKey;
use IPC::Open3;
use Time::HiRes qw(sleep);

my $DEBUG = 0;

$SIG{TSTP} = sub { };
#TODO: Add clean shutdown for $SIG{TERM} and $SIG{KILL}

my $term = new Term::ReadLine 'ProgramName';
print "DEBUG Using: ", $term->ReadLine, "\n" if ($DEBUG);
$term->MinLine();
$term->ornaments(0);

my ($pm_stdin_h, $pm_stdout_h, $pm_stderr_h);
my $pmmp_pid = open3($pm_stdin_h, $pm_stdout_h, $pm_stderr_h, 'java -Xmx1024M -Xms1024M -jar minecraft_server.jar nogui')
    or die "open3() failed $!";

ReadMode('raw', $pm_stdout_h);
ReadMode('raw', $pm_stderr_h) if defined $pm_stderr_h;
ReadMode('raw');

my $key_pressed = "";
my $key_buffer = "";
my $key_preput = "";
my $pm_stdout_buffer = "";
my $pm_stderr_buffer = "";

my @keys_pressed = ();

my $idle = 1;

my $result = 0;

while (1) {
  $idle = 1;

  # Check STDIN for either '/' or up-arrow
  $key_pressed = ReadKey(-1);
  if (defined $key_pressed) {
    push(@keys_pressed, ord($key_pressed));
    shift(@keys_pressed) if (scalar(@keys_pressed)>3);
    if ($DEBUG) {
      print("DEBUG Keys Pressed:");
      foreach my $key (@keys_pressed) {
        printf(" #%x", $key);
      };
      print "\n";
    };
  };
  $key_pressed = 0 unless defined $key_pressed;
  last if ($key_pressed eq "q");
  if ($key_pressed eq "/") {
    $key_pressed  = 1;
    $idle         = 0;
    @keys_pressed = ();
    $key_preput   = "";
  } elsif ((scalar(@keys_pressed) == 3) and
           ($keys_pressed[0] == 0x1b) and
           ($keys_pressed[1] == 0x5b) and
           ($keys_pressed[2] == 0x41)) {
    # Detect control escape sequences
    # Up Arrow = #1b #5b #41
    $key_pressed  = 1;
    $idle         = 0;
    @keys_pressed = ();
    $key_preput   = "yes";
  } else {
    $key_pressed  = 0;
    $idle         = 0;
  };

  # Pipe full output lines from PocketMine-MP
  if ((defined $pm_stdout_h) &&
      (pipe_lines($pm_stdout_h,$pm_stdout_buffer,'<'))) { $idle = 0; };
  if ((defined $pm_stderr_h) &&
      (pipe_lines($pm_stderr_h,$pm_stderr_buffer,'!'))) { $idle = 0; };

  # If keyboard pressed '/' or up-arrow earlier, capture a line of input
  if ($key_pressed) {
    if ($key_preput eq "") {
      $key_buffer = readline_signaltrap($term,'/');
      $term->add_history($key_buffer) unless ($key_buffer eq "");
    } else {
      $key_preput = $term->history_get($term->Attribs->{history_length});
      $term->remove_history($term->Attribs->{history_length}-1);
      $key_buffer = readline_signaltrap($term,'/',$key_preput);
      $term->add_history($key_preput);
      $term->add_history($key_buffer) unless ($key_buffer eq "");
      $key_preput = "";
    };
  };

  # Pipe full output lines from PocketMine-MP (Again)
  if ((defined $pm_stdout_h) &&
      (pipe_lines($pm_stdout_h,$pm_stdout_buffer,'<'))) { $idle = 0; };
  if ((defined $pm_stderr_h) &&
      (pipe_lines($pm_stderr_h,$pm_stderr_buffer,'!'))) { $idle = 0; };

  # Write the line of input from keyboard into PocketMine-MP's STDIN
  if ($key_buffer ne "") {
    printf $pm_stdin_h $key_buffer . "\n";
    $key_buffer = "";
  };

  # Check if PocketMine-MP is still running
  my $res = waitpid($pmmp_pid, WNOHANG);
  if ($res == -1) {
    $result = $? >> 8;
    printf "Some error occurred %d\n", $result;
    last;
  };
  if ($res) {
    $result = $? >> 8;
    printf "PocketMine-MP ended with error code %d\n", $result;
    my $count_down = 5;
    print "Stopping container in:\n";
    while ($count_down >= 0) {
      printf "\t%d%s\n", $count_down, ($count_down>0)?("..."):(".");
      $count_down -= 1;
      sleep(1);
    };
    print "Goodbye\n";
    last;
  };

  sleep(0.1);
};

ReadMode('normal');

close($pm_stdin_h)  if defined $pm_stdin_h;
close($pm_stdout_h) if defined $pm_stdout_h;
close($pm_stderr_h) if defined $pm_stderr_h;

exit($result);

sub pipe_lines {
    my $fh     = $_[0];
    my $buf    = $_[1];
    my $prefix = $_[2];
    my $key    = "";
    my $result = 0;
    $key = ReadKey(-1, $fh);
    while (defined $key) {
      $result = 1;
      $buf .= $key;
      if ($key eq "\n") {
        print $prefix . $buf;
        $buf = "";
      };
      $key = ReadKey(-1, $fh);
    };
    $_[1] = $buf;
    return $result;
};

sub readline_signaltrap {
    my $term = shift;
    my $prompt = shift;
    my $preput;
    my $child_pid;
    my $wait = 1;
    my $segment_id = shmget (IPC_PRIVATE, 0x1000, IPC_CREAT | IPC_EXCL | S_IRUSR | S_IWUSR);

    if (scalar(@_) > 0) {
      $preput = shift;
    };

    if ($child_pid = fork) {
       my $value;
       $SIG{INT}  = sub { print "CTRL+C\n"; $wait = 0; };
       $SIG{TSTP} = sub { };
       print "DEBUG (parent)\n" if ($DEBUG);
       while ($wait and not waitpid($child_pid, WNOHANG)) {
           sleep(0.1);
       };
       if (not $wait) {
           print "DEBUG POST CTRL+C\n" if ($DEBUG);
           kill 'KILL', $child_pid;
           print "DEBUG POST KILL\n" if ($DEBUG);
           $value = "";
       } else {
           print "DEBUG CHILD RETURNED\n" if ($DEBUG);
           shmread($segment_id, $value, 0, 0x1000);
           print "DEBUG SHM READ\n" if ($DEBUG);
       };
       shmctl($segment_id, IPC_RMID, 0);
       $value =~ s/\0//g;
       return $value;
    } else {
       my $value;
       print "DEBUG (child)\n" if ($DEBUG);
       ReadMode('normal');
       $|=1;
       if (defined $preput) {
         $value = $term->readline($prompt,$preput);
       } else {
         $value = $term->readline($prompt);
       };
       $|=0;
       ReadMode('raw');
       shmwrite($segment_id, $value, 0, 0x1000) || die "$!";
       exit(0);
    };
};

