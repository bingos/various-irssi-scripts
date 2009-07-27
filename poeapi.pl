use Irssi;
use Irssi::Irc;
use Glib;
use POE qw(Loop::Glib);
use POE::API::Peek;

my $api = POE::API::Peek->new();

sub poe_sessions {
  my @sessions = $api->session_list();
  my @output;
  foreach my $session ( @sessions ) {
     my $record = [ ];
     push @$record, $api->resolve_session_to_id($session);
     push @$record, $api->session_memory_size($session);
     push @$record, join( ' ', $api->session_alias_list($session) );
     push @output, $record;
  }
  Irssi::active_win()->print( join(" ",@$_) ) for @output;
}

Irssi::command_bind("sessions", "poe_sessions");
