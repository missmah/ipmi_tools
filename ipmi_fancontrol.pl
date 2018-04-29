#!/usr/bin/perl
use strict;
use warnings;
use List::Util qw[min max];

# This script controls SuperMicro server fan speeds via IPMI in response to CPU and GPU Temperatures.
# This script is tested on the SuperMicro X10 4027GR-TRT Server. It may work on other X9/X10/X11 motherboards.
#
# NOTE: The script puts your server into "Full Fan Speed Mode", and then modifies what "Full Speed" means,
#       You have to manually use IPMI to set it to e.g. "Optimal" when you're not using the script.
#
# NOTE: You use this script at your own risk, and no warranty is provided. Do not use in produciton environments.
#
# Author: Layla Mah <layla@insightfulvr.com>

# System Configuration
my $number_of_cpus      = 2; # Number of CPUs to search for
my $number_of_gpus      = 4; # Number of GPUs to search for
my $number_of_fans      = 8; # Number of FANs to search for
my $number_of_fanbanks  = 4; # Number of BANKs of FANs to update
my $min_temp_change     = 5; # *C minimum change to actually cause a fan speed update
my $seconds_to_sleep    = 5; # Number of seconds to sleep between update loops

# IPMI Configuration
my $ipmi_username       = "username_goes_here";
my $ipmi_password       = "password_goes_here";
my $ipmi_ipaddress      = "ip_address_goes_here";
my $ipmi_connectmode    = "lan";
my $ipmi_cmd_listall    = "sdr list full";
my $ipmi_preamble       = 'ipmitool -I $ipmi_connectmode -U $ipmi_username -P $ipmi_password -H $ipmi_ipaddress';

# CPU Temp -> Fan Speed Mappings
my %cpu_temp_to_fan_speed;
   $cpu_temp_to_fan_speed{80} = 0x64;
   $cpu_temp_to_fan_speed{75} = 0x56;
   $cpu_temp_to_fan_speed{70} = 0x48;
   $cpu_temp_to_fan_speed{60} = 0x40;
   $cpu_temp_to_fan_speed{55} = 0x32;
   $cpu_temp_to_fan_speed{50} = 0x16;
   $cpu_temp_to_fan_speed{10} = 0x8;

# GPU Temp -> Fan Speed Mappings
my %gpu_temp_to_fan_speed;
   $gpu_temp_to_fan_speed{93} = 0x64;
   $gpu_temp_to_fan_speed{90} = 0x56;
   $gpu_temp_to_fan_speed{85} = 0x48;
   $gpu_temp_to_fan_speed{80} = 0x40;
   $gpu_temp_to_fan_speed{75} = 0x32;
   $gpu_temp_to_fan_speed{70} = 0x24;
   $gpu_temp_to_fan_speed{65} = 0x22;
   $gpu_temp_to_fan_speed{50} = 0x20;
   $gpu_temp_to_fan_speed{40} = 0x18;
   $gpu_temp_to_fan_speed{30} = 0x16;
   $gpu_temp_to_fan_speed{10} = 0x8;

# Below this line follows the actual implementation of the script

my $g_current_fan_duty_cycle = 0;
my $g_current_gpu_temp = 0;
my $g_current_cpu_temp = 0;
my $g_last_set_cpu_temp = 0;
my $g_last_set_gpu_temp = 0;

sub Internal_DoSetFanSpeed
{
  my ( $fan_speed ) = @_;

  foreach my $fanbank (0..$number_of_fanbanks)
  {
    my $hex_fanbank = sprintf( "0x%x", $fanbank );
    `ipmitool -I $ipmi_connectmode -U $ipmi_username -P $ipmi_password -H $ipmi_ipaddress raw 0x30 0x70 0x66 0x01 $hex_fanbank $fan_speed`;
  }
}

sub SetFanSpeed
{
  my ( $fan_speed ) = @_;

  my $cpu_temp_difference = $g_current_cpu_temp - $g_last_set_cpu_temp;
  my $gpu_temp_difference = $g_current_gpu_temp - $g_last_set_gpu_temp;
  if( ( (abs $cpu_temp_difference) > $min_temp_change ) or ( (abs $gpu_temp_difference) > $min_temp_change ) )
  {
    # Set all 4 fan banks to operate at $fan_speed duty cycle (0x0-0x64 valid range)
    print "\n";
    print "******************** Updating Fan Speeds ********************\n";
    print "We last updated fan speed $cpu_temp_difference *C ago (CPU Temperature).\n";
    print "We last updated fan speed $gpu_temp_difference *C ago (GPU Temperature).\n";
    print "Current CPU Temperature is $g_current_cpu_temp *C.\n";
    print "Current GPU Temperature is $g_current_gpu_temp *C.\n";
    print "Setting Fan Speed on all fan banks to $fan_speed\n";
    print "*************************************************************\n";
    
    $g_last_set_cpu_temp = $g_current_cpu_temp;
    $g_last_set_gpu_temp = $g_current_gpu_temp;
    $g_current_fan_duty_cycle = $fan_speed;

    Internal_DoSetFanSpeed( $fan_speed );
  }
}

sub UpdateFanSpeed
{ 
  # Gather statistics for fan speed and CPU Temp and stuch
  my $ipmi_output = `ipmitool -I $ipmi_connectmode -U $ipmi_username -P $ipmi_password -H $ipmi_ipaddress $ipmi_cmd_listall`;
  my @vals = split( "\n", $ipmi_output );

  my $current_cpu_temp = 0;
  my $current_gpu_temp = 0;
  my $min_fan_speed = 30000;
  my $max_fan_speed = 0;

  foreach my $value (@vals)
  {
  
    foreach my $fan (1..$number_of_fans)
    {
      if( $value =~ /^(FAN$fan)\s.*\s(\d+)\s.*RPM.*/gi )
      {
        #print "Value   : $value\n";
        #print "Matched : $1\n";
        #print "FanSpeed: $2 RPM\n";
        print "$1 ....: $2 RPM\n";
        my  $fan_speed = $2;
        $min_fan_speed = min( $fan_speed, $min_fan_speed );
        $max_fan_speed = max( $fan_speed, $max_fan_speed );
      }
    } # foreach my $fan (1..$number_of_fans)
     
    foreach my $cpu (1..$number_of_cpus)
    {
      if( $value =~ /^(CPU$cpu\sTemp).*\s(\d+)\s.*degrees\sC.*/gi )
      {
        #print "Value  : $value\n";
        #print "Matched: $1\n";
        #print "Temp   : $2 degrees C\n";
        print "$1: $2 degrees C\n";
        my      $cpu_temp = $2;
        $current_cpu_temp = max( $cpu_temp, $current_cpu_temp );
      }
    } # foreach my $cpu (1..$number_of_cpus)

    foreach my $gpu (1..$number_of_gpus)
    {
      if( $value =~ /^(GPU$gpu\sTemp).*\s(\d+)\s.*degrees\sC.*/gi )
      {
        #print "Value  : $value\n";
        #print "Matched: $1\n";
        #print "Temp   : $2 degrees C\n";
        print "$1: $2 degrees C\n";
        my      $gpu_temp = $2;
        $current_gpu_temp = max( $gpu_temp, $current_gpu_temp );
      }
    } # foreach my $gpu (1..$number_of_gpus)
    
  } # foreach my $value (@vals)

  $g_current_cpu_temp = $current_cpu_temp;
  $g_current_gpu_temp = $current_gpu_temp;

  print "Maximum CPU Temperature Seen: $current_cpu_temp degrees C.\n";
  print "Maximum GPU Temperature Seen: $current_gpu_temp degrees C.\n";
  print "Current Minimum Fan Speed: $min_fan_speed RPM\n";
  print "Current Maximum Fan Speed: $max_fan_speed RPM\n";

  my $desired_fan_speed = 0x0;
 
  my @cpu_temps = keys %cpu_temp_to_fan_speed;
  for my $cpu_temp (@cpu_temps)
  {
    if( $current_cpu_temp > $cpu_temp )
    {
      # If the current CPU temperature is higher than the temperature enumerated by this hash lookup,
      # Then set the desired fan speed (if our value is larger than the existing value)
      $desired_fan_speed = max( $cpu_temp_to_fan_speed{ $cpu_temp }, $desired_fan_speed );
      #print "The fan speed setting for CPU Temp $cpu_temp *C is $cpu_temp_to_fan_speed{$cpu_temp} % duty cycle\n";
    }
  }

  my @gpu_temps = keys %gpu_temp_to_fan_speed;
  for my $gpu_temp (@gpu_temps)
  {
    if( $current_gpu_temp > $gpu_temp )
    {
      # If the current gPU temperature is higher than the temperature enumerated by this hash lookup,
      # Then set the desired fan speed (if our value is larger than the existing value)
      $desired_fan_speed = max( $gpu_temp_to_fan_speed{ $gpu_temp }, $desired_fan_speed );
      #print "The fan speed setting for GPU Temp $gpu_temp *C is $gpu_temp_to_fan_speed{$gpu_temp} % duty cycle\n";
    }
  }
  
  if( $desired_fan_speed == 0x0 )
  {
    print "\n***** ERROR: Failed to determine a desired fan speed. Forcing fans to 100% duty cycle as a safety fallback measure. *****\n";
    $desired_fan_speed = 0x64;
  }

  print "Current Fan Duty Cycle: $g_current_fan_duty_cycle%\n";
  print "Desired Fan Duty Cycle: $desired_fan_speed%\n";

  SetFanSpeed( $desired_fan_speed );

}

print "Setting Fan mode to FULL SPEED.\n";
# Ensure Fan Mode is set to Full Speed
`ipmitool -I $ipmi_connectmode -U $ipmi_username -P $ipmi_password -H $ipmi_ipaddress raw 0x30 0x45 0x01 0x01`;

while( 1 )
{
  print "\n";
  print "=================================================================\n";
  print "Calling UpdateFanSpeed()...\n";
  print "=================================================================\n";
  UpdateFanSpeed();
  print "=================================================================\n";
  print "Update Complete - going to sleep for $seconds_to_sleep seconds...\n";
  print "=================================================================\n";
  sleep $seconds_to_sleep;
}
