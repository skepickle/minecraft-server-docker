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

$SIG{INT}  = 'IGNORE';
$SIG{TERM} = \&sigterm_handler;

my $term = new Term::ReadLine 'ProgramName';
print "DEBUG Using: ", $term->ReadLine, "\n" if ($DEBUG);
$term->MinLine();
$term->ornaments(0);

my ($mcs_in_h, $mcs_out_h, $mcs_err_h);
my $mcs_pid =
  open3($mcs_in_h, $mcs_out_h, $mcs_err_h,
        "java $ENV{JAVA_OPTS} -jar minecraft_server.jar nogui")
  or die "open3() failed $!";

ReadMode('raw', $mcs_out_h);
ReadMode('raw', $mcs_err_h) if defined $mcs_err_h;
ReadMode('raw');

my ($key_pressed, $key_buffer, $key_preput) = ("", "", "");
my ($mcs_out_buffer, $mcs_err_buffer) = ("", "");
my $sigterm = 0;

my @keys_pressed = ();

my $idle = 1;

my $result = 0;

while (1) {
  # Pipe full output lines from Minecraft Server
  flush_output_pipes($mcs_out_h, $mcs_out_buffer, $mcs_err_h, $mcs_err_buffer);

  $idle = 1;

  #TODO: check for presence of special action files
  if (-e "..SAVE-ALL") {
    unlink("..SAVE-ALL");
  };

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

  # If keyboard pressed '/' or up-arrow earlier, capture a line of input
  if ($key_pressed) {
    if ($key_preput eq "") {
      ($key_buffer, $sigterm) = readline_signaltrap($term,'/');
      $term->add_history($key_buffer) unless ($key_buffer eq "");
    } else {
      $key_preput = $term->history_get($term->Attribs->{history_length});
      $term->remove_history($term->Attribs->{history_length}-1);
      ($key_buffer, $sigterm) = readline_signaltrap($term,'/',$key_preput);
      $term->add_history($key_preput);
      $term->add_history($key_buffer) unless ($key_buffer eq "");
      $key_preput = "";
    };
  };

  if ($sigterm) { sigterm_handler(); };

  if (rindex($key_buffer, "/", 0) == 0) {
    # Recognize "//" prefix in input and perform wrapper function instead of passing through directly to Minecraft Server
    printf "double slash?\n";
    $key_buffer = "";
  } elsif ($key_buffer ne "") {
    # Write the line of input from keyboard into Minecraft Server STDIN
    printf $mcs_in_h $key_buffer . "\n";
    $key_buffer = "";
  };

  # Check if Minecraft Server is still running
  my $res = waitpid($mcs_pid, WNOHANG);
  my $err = $?;
  if ($res == -1) {
    $result = $err >> 8;
    printf "Some error occurred %d\n", $result;
  };
  if ($res) {
    $result = $err >> 8;
    printf "Minecraft server java process exited with error code %d\n", $result;
    printf "res = %d\n", $res;
    printf "err = %d\n", $err;
  };
  last if ($res != 0);

  # Pipe full output lines from Minecraft Server
  flush_output_pipes($mcs_out_h, $mcs_out_buffer, $mcs_err_h, $mcs_err_buffer);
  sleep(0.1);
};

ReadMode('normal');

close($mcs_in_h)  if defined $mcs_in_h;
close($mcs_out_h) if defined $mcs_out_h;
close($mcs_err_h) if defined $mcs_err_h;

exit($result);

###############################################################################

sub sigterm_handler {
  my ($r, $e, $z);
  print("# Received SIGTERM\n");
  printf $mcs_in_h "stop\n";
  # Pipe full output lines from Minecraft Server
  while (1) {
    flush_output_pipes($mcs_out_h, $mcs_out_buffer, $mcs_err_h, $mcs_err_buffer);
    $r = waitpid($mcs_pid, WNOHANG);
    $e = $?;
    if ($r == -1) {
      $z = $e >> 8;
      printf "Some error occurred %d\n", $z;
      last;
    };
    if ($r) {
      $z = $e >> 8;
      printf "Minecraft server java process exited with error code %d\n", $z;
      printf "res = %d\n", $r;
      printf "err = %d\n", $e;
      last;
    };
    flush_output_pipes($mcs_out_h, $mcs_out_buffer, $mcs_err_h, $mcs_err_buffer);
    sleep(0.1);
  };
  exit($z);
};

sub pipe_lines {
  my $fh     = $_[0];
  my $buf    = $_[1];
  my $prefix = $_[2];
  my $result = 0;
  my $key    = ReadKey(-1, $fh);
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
  my ($term, $prompt) = (shift, shift);
  my ($preput, $child_pid, $wait, $sigterm_rl, $segment_id);
  $wait = 1;
  $sigterm_rl = 0;
  $segment_id = shmget(IPC_PRIVATE, 0x1000, IPC_CREAT | IPC_EXCL | S_IRUSR | S_IWUSR);

  if (scalar(@_) > 0) {
    $preput = shift;
  };

  if ($child_pid = fork) {
    my $value;
    local $SIG{INT}  = sub { print "\n"; print "CTRL+C\n" if ($DEBUG); $wait = 0; };
    local $SIG{TERM} = sub { print("# Received SIGTERM\n"); $sigterm_rl = 1; $wait = 0; };
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
    return ($value, $sigterm_rl);
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

sub flush_output_pipes {
  my ($out_h, $out_b, $err_h, $err_b) = (shift, shift, shift, shift);
  pipe_lines($out_h, $out_b,'< ') if (defined $out_h);
  pipe_lines($err_h, $err_b,'! ') if (defined $err_h);
};

