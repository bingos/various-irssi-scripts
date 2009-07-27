use strict;
use warnings;
use Irssi;
use Irssi::Irc;
use Glib;
use POE qw(Loop::Glib Session::Irssi);
use POE::Component::Server::IRC;

my $name = 'meep';
my $network = 'meepNET';

my $motd = [ ];
open my $data, "<", "~/.irssi/scripts/motd.txt" or die "$!\n";
while (<$data>) {
  chomp;
  push @$motd, $_;
}
close $data;

my $pocosi = POE::Component::Server::IRC->spawn( 
	alias  => 'IRCD',
	config =>
	{
		servername => $name,
		network    => $network,
		motd 	     => $motd,
	},
);

POE::Session::Irssi->create(
   inline_states => {
			_start    => \&_start,
			_unload   => \&_unload,
			_shutdown => \&_shutdown,
   },
   heap => { ircd => $pocosi },
);

sub _start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $kernel->alias_set('Irssi::Script::ircd');
  $kernel->sig( 'unload', '_unload' );
  $heap->{ircd}->yield( 'register' );
  $heap->{ircd}->add_auth( mask => '*@localhost', spoof => 'staff.meep.net', no_tilde => 1 );
  $heap->{ircd}->add_auth( mask => '*@127.0.0.1', spoof => 'staff.meep.net', no_tilde => 1 );
  $heap->{ircd}->add_auth( mask => '*@*' );
  $heap->{ircd}->add_listener( port => 6669 );
  $heap->{ircd}->add_operator( { username => 'bingos', password => '**********' } );
  $heap->{ircd}->add_peer( name => 'logserv.meep.net', pass => '********', rpass => '*********', type => 'r', raddress => '192.168.0.1', rport => 7667, auto => 1 );
  return;
}

sub _shutdown {
  $POE::Kernel::poe_kernel->alias_remove($_) for $POE::Kernel::poe_kernel->alias_list();
  $POE::Kernel::poe_kernel->alarm_remove_all();
  $POE::Kernel::poe_kernel->call( 'IRCD', 'shutdown' );
  print "UNLOADED: Irssi::Script::ircd";
  return;
}

sub _unload {
  my $package = $_[ARG1];
  $POE::Kernel::poe_kernel->call( $package, '_shutdown' );
  $POE::Kernel::poe_kernel->sig_handled();
}

