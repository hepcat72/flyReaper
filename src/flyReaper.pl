#!/usr/bin/perl

#USAGE: Run with no options to get usage or with --help for basic details

#Robert W. Leach
#Princeton University
#Carl Icahn Laboratory
#Lewis Sigler Institute for Integrative Genomics
#Bioinformatics Group
#Room 137A
#Princeton, NJ 08544
#rleach@princeton.edu
#Copyright 2016

#Template version: 1.0

use warnings;
use strict;
use CommandLineInterface;

my $min_stat_vals    = 240;
my $stationary_value = [];
my $stat_val_default = [0,'NaN'];
my $alive_str        = "still alive";
my $never_moved_str  = 'dead on arrival';
my $stat_pattern     = '^' . quotemeta($stationary_value) . '$';

setScriptInfo(VERSION => '1.3',
              CREATED => '10/24/2016',
              AUTHOR  => 'Robert William Leach',
              CONTACT => 'rleach@princeton.edu',
              COMPANY => 'Princeton University',
              LICENSE => 'Copyright 2017',

              HELP    => << '              END_HELP'
This script takes an output file from flyMultiPlateScript.m (a fly motion tracker matlab script) and finds the first instance of N contiguous occurrences of a stationary value and reports the inferred time of death for each well.
              END_HELP

	     );

addInfileOption(GETOPTKEY   => 'i|motion-file=s',
		REQUIRED    => 1,
		PRIMARY     => 1,
		SMRY_DESC   => 'File of recorded fly activity.',

		DETAIL_DESC => << '                END_DETAIL'

Comma-delimited text file (e.g. '.csv') where the first column is time in seconds and each subsequent column is a value indicating some form of fly activity/change.

                END_DETAIL
		,

		FORMAT_DESC => << '                END_FORMAT'

Comma-delimited text file where the first column is time in seconds and each subsequent column is a value indicating some form of fly activity/change.  The number of columns must be consistent on every row.  The first row is composed of column headers.

Example:

time_sec,cam:1_plate:1_well:A1_displacement(mm),cam:1_plate:1_well:B1_displacement(mm),cam:1_plate:1_well:C1_displacement(mm)
60.2286,NaN,NaN,NaN
120.117,17.3958,55.5988,46.0784
180.156,27.4204,31.9255,44.7029
240.142,NaN,5.90888,40.5971
...

                END_FORMAT

	       );

addOption(GETOPTKEY   => 'n|min-stationary-vals=s',
	  GETOPTVAL   => \$min_stat_vals,
	  DEFAULT     => $min_stat_vals,
	  SMRY_DESC   => 'Number of stationary values to infer death.',
	  DETAIL_DESC => << '                END_DETAIL'

When the value stored by the matlab script for a fly shows no activity for this contiguous number of recordings, the fly is presumed to be dead and the time of the first appearance of inactivity in that contiguous block of inactive values is what is reported as the presumed time of death.  Sometimes a fly my be stationary, but alive.  This option indicates how many consecutive inactivity/stationary values are required to infer death.  Note, the time between the recording of motion is set inside the script, and should be taken into account when setting this value.  Its current default is 60 seconds.  Note, if activity is detected after the first time of inferred death, a warning will be generated.  Must be greater than 1.")));

                END_DETAIL
	 );

addArrayOption(GETOPTKEY   => 's|stationary-value=s',
	       GETOPTVAL   => $stationary_value,
	       DEFAULT     => '"' . join('","',@$stat_val_default) . '"',
	       SMRY_DESC   => 'Inactivity value(s).',
	       DETAIL_DESC => << '                END_DETAIL'

Value(s) indicating no activity (e.g. "NaN" or "0").  The entire value is matched and is case insensitive.  If multiple values are supplied, any of the supplied values will be deemed an inactivity value.  Empty string is allowed (e.g. -s "").  This is the value whose repeated contiguous occurrences (see -n) are what is used to infer death.

                END_DETAIL
	 );

processCommandLine();

if($min_stat_vals < 2)
  {
    error("-n: [$min_stat_vals] must be greater than 1.");
    quit(1);
  }

if(!defined($stationary_value) || scalar(@$stationary_value) == 0)
  {$stationary_value = [@$stat_val_default]}

$stat_pattern = '^(' . join('|',map {quotemeta($_)} @$stationary_value) . ')$';

while(my $inputFile = getInfile(ITERATE => 1))
  {
    my $outputFile        = getOutfile();
    my $line_num          = 0;
    my @inactive_counters = ();
    my @headers           = ();
    my @times_of_death    = ();
    my @last_first_vals   = ();
    my @lazari            = ();
    my @num_deaths        = ();
    my @zombie_activity   = ();
    my $first_time        = '';

    openIn(*IN,$inputFile)    || next;
    openOut(*OUT,$outputFile) || next;

    while(getLine(*IN))
      {
	$line_num++;
	verboseOverMe({FREQUENCY => 100},
		      "[$inputFile] Reading line: [$line_num].");

	chomp;

	next if(/^#/ || /^\s*$/);

	my @cols = split(/,/,$_,-1);

	if(scalar(@cols) < 2)
	  {
	    warning("Unable to parse columns on line [$line_num]: [$_].");
	    next;
	  }

	#Process the header line if we haven't done so already
	if(scalar(@headers) == 0)
	  {
	    if($_ !~ /^time_sec/ && $_ !~ /well/)
	      {
		warning("Expected headers on the first line of file ",
			"[$inputFile], but did not file the time_sec header ",
			"or any 'well' headers.  Setting sequential headers.");

		@headers = (0..$#cols);

		#Account for the time column
		shift(@headers);
	      }
	    else
	      {
		@headers = @cols;

		#The matlab script tends to add a trailing comma
		if($cols[-1] eq '')
		  {pop(@headers)}

		#Take off the time
		shift(@headers);

		next;
	      }
	  }

	my $time = shift(@cols);

	if($first_time eq '')
	  {$first_time = $time}

	#Make sure the headers are consistent with the number of column in each
	#row
	if(scalar(@headers) != scalar(@cols))
	  {
	    warning("Encountered a row on line [$line_num] of file ",
		    "[$inputFile] with ",
		    (scalar(@headers) < scalar(@cols) ? "more" : "fewer"),
		    " columns [",scalar(@cols),"] than the number of column ",
		    "headers [",scalar(@headers),"].  Filling in headers ",
		    "with sequential numbers.");

	    while(scalar(@headers) < scalar(@cols))
	      {
		my $nh = scalar(@headers) + 1;
		push(@headers,$nh);
	      }
	  }

	#If this is the first row of data
	if(scalar(@inactive_counters) == 0)
	  {
	    @inactive_counters = map {/$stat_pattern/i ? 1 : 0} @cols;
	    @times_of_death    = map {$alive_str} @cols;
	    @lazari            = map {0} @cols;
	    @last_first_vals   = map {/$stat_pattern/i ? $time : ''} @cols;
	    @num_deaths        = map {0} @cols;
	    @zombie_activity   = map {0} @cols;
	  }
	else
	  {
	    #Error-check the number of columns
	    if(scalar(@inactive_counters) != scalar(@cols))
	      {
		warning("Encountered a row on line [$line_num] of file ",
			"[$inputFile] with ",
			(scalar(@inactive_counters) < scalar(@cols) ?
			 "more" : "fewer")," columns [",scalar(@cols),
			"] than previous rows [",scalar(@inactive_counters),
			"].");

		while(scalar(@inactive_counters) < scalar(@cols))
		  {
		    push(@inactive_counters,0);
		    push(@times_of_death,$alive_str);
		    push(@lazari,0);
		    push(@last_first_vals,'');
		    push(@num_deaths,0);
		    push(@zombie_activity,0);
		  }
	      }

	    foreach my $i (0..$#cols)
	      {
		#If no motion was recorded since the last row
		if($cols[$i] =~ /$stat_pattern/i)
		  {
		    $inactive_counters[$i]++;

		    #If this is the first time we've seen a nan since seeing a
		    #number
		    if($last_first_vals[$i] eq '')
		      {$last_first_vals[$i] = $time}

		    #If we've counted the number of inactivity values that
		    #imply death AND this is the first time it has "died"
		    if($inactive_counters[$i] == $min_stat_vals &&
		       $times_of_death[$i] eq $alive_str)
		      {
			$times_of_death[$i] = $last_first_vals[$i];
			$num_deaths[$i]++;
		      }
		    elsif($inactive_counters[$i] == $min_stat_vals)
		      {
			warning("The zombie fly in [$headers[$i]] appears to ",
				"have died again ([$lazari[$i]] times).");
			$num_deaths[$i]++;
		      }
		  }
		#Else, motion was detected - life!
		else
		  {
		    #If this fly was already supposed to have died
		    if($times_of_death[$i] ne $alive_str)
		      {
			$zombie_activity[$i]++;

			if($lazari[$i] == 0)
			  {
			    warning("Lazarus! Motion detected after presumed ",
				    "death of fly [$headers[$i]] on line ",
				    "[$line_num] of file [$inputFile].");
			    $lazari[$i] = 1;
			  }
		      }

		    $inactive_counters[$i] = 0;
		    $last_first_vals[$i]   = '';
		  }
	      }
	  }
      }

    print("WellID\t",join(',',@headers),"\n",
	  "Time of Death\t",
	  join(',',map {$_ eq $first_time ? $never_moved_str : $_}
	       @times_of_death),"\n",

	  #If there are any flies still alive, print the number of inactivity
	  #values at the end of the file for that fly
	  (scalar(grep {$_ eq $alive_str} @times_of_death) == 0 ? '' :
	   "Num stationary values at end\t",
	   join(',',
		map {$times_of_death[$_] eq $alive_str ?
		       $inactive_counters[$_] : ''} 0..$#inactive_counters),
	   "\n"),

	  #If there were any lazari
	  (scalar(grep {$_} @lazari) == 0 ? '' :

	   #Print the fact that the fly is risen from the dead
	   ("\nLazari\t",join(',',map {$_ ? 'Lazarus' : ''} @lazari),"\n",

	    #Print the number of deaths that were detected
	    "Number of Deaths Detected\t",join(',',@num_deaths),"\n",

	    #Print the number of times activity was detected after first death
	    "Zombie Activity\t",join(',',@zombie_activity),"\n")));

    closeIn(*IN);
    closeOut(*OUT);
  }
