#!/usr/bin/perl
#Generated using perl_script_template.pl

#USAGE: Run with no options to get usage or with --extended for more details

my $software_version_number = '1.0';                    #Global
my $created_on_date         = 'DATE HERE';              #Global

#Robert W. Leach
#Princeton University
#Carl Icahn Laboratory
#Lewis Sigler Institute for Integrative Genomics
#Bioinformatics Group
#Room 133A
#Princeton, NJ 08544
#rleach@genomics.princeton.edu
#Copyright 2015

##
## TEMPLATE DESCRIPTION:
##   This is a template for writing perl scripts that includes numerous bells
##   and whistles that you normally wouldn't have in a quickly created script.
##   This script has lots of features and they will all work with virtually any
##   file-processing code.  Things like, fancy command line handling, verbose
##   messages that overwrite each other, error messages with trace strings when
##   run in debug mode, a summary of running time and error types at the end of
##   a run, standardized usage and help output, detection of standard input and
##   redirected output, detection of existing output files to prevent
##   accidental over-writing of files, and more.
##
## TEMPLATE INSTRUCTIONS:
##   1. Save this file with another name or copy its contents to a new file.
##   2. Change the software_version_number variable at the top.
##   3. Edit the copyright information at the top of the script & in the help
##      subroutine.  Put the creation date where it says "DATE HERE" in your
##      desired format.
##   4. Edit the help and usage subroutines at the bottom of this script.
##   5. Enter your code anywhere, but generally in the spaces provided,
##      commented with all-caps:
##        DECLARE VARIABLES HERE
##          Add new variables here and edit the defaults above, as marked
##        VALIDATE COMMAND LINE OPTIONS HERE
##          Here is where you enforce required options & check values supplied
##          by the user.  Examples of variables for inputs & outputs are
##          provided below
##        ENTER YOUR COMMAND LINE PARAMETERS HERE AS BELOW
##          NOTE: The <> option has no flag.  Any arguments without flags will
##          be mixed with the input files (a common unix convention for input
##          files).  Optional STDIN input is detected and unless it's
##          explicitly placed among the input files via the dash character
##          ('-'), it is considered to be the first file supplied with its own
##          -i flag.  You may add input file flags as you wish.
##        ENTER INPUT FILE ARRAYS HERE
##          These are 2D arrays of file names where the first dimension/index
##          indicates the number of the flag a file was submitted with and the
##          second dimension/index indicates the number of the file submitted
##          with that flag.
##        ENTER SUFFIX ARRAYS HERE IN SAME ORDER
##          These are 1D arrays of file extensions.  The arrays are in the same
##          order as the input file arrays above.  Each input file type may
##          have multiple output file suffixes (of different types).
##        ENTER YOUR PRE-FILE-PROCESSING CODE HERE
##        ENTER YOUR FILE-PROCESSING CODE HERE
##          All outputs will go to standard out unless an output file suffix
##          is provided, in which case the input file name is used to create
##          an output file name and selected by default when opened.  So you
##          may write your code as if you are printing to standard out and it
##          will go into the correct output file.
##       ENTER YOUR POST-FILE-PROCESSING CODE HERE
##
## TEMPLATE RESOURCES
##   usage
##     This subroutine prints a description of how to use the script.
##     This subroutine must be edited.  A template format is supplied.
##   help
##     This subroutine prints helpful text about the script on standard out.
##     This subroutine must be edited.  A template format is supplied.
##   verbose subroutine
##     This subroutine prints verbose messages if the verbose flag is supplied.
##   verboseOverMe
##     This subroutine prints verbose messages followed by a carriage return.
##     Note, all subs that output to STDERR keep track of the length of the
##     last line output so that STDERR messages look clean.
##   error
##     This subroutine prints error messages passed in and prepends a string to
##     each line of error output that looks like this:
##     ERROR$error_number:$script_name:$calling_sub_backtrace
##     A subroutine trace is provided with line numbers.  This sub will not
##     overwrite verbose messages in overwrite mode.
##   warning
##     This subroutine prints warning messages passed in and prepends a string
##     to each line of warning output that looks like this:
##     WARNING$warning_number:
##     This sub will not overwrite verbose messages in overwrite mode.
##   getLine
##     This sub is supplied to handle the \r line delimiter in addition to the
##     default: \n and replaces \r's and a couple common compounds of \r's with
##     \n's.  It works the same as the angle brackets (<>).  Perl on some
##     systems does not intuitively handle carriage returns.
##   debug
##     This subroutine prints debug messages passed in and prepends a string to
##     each line of debug output that looks like this:
##     DEBUG$debug_number:LINE$line_num:
##     This sub will not overwrite verbose messages in overwrite mode.
##   markTime
##     This subroutine is provided to allow easy running time monitoring.  It
##     creates and stores all time marks in a global array.  A time mark is
##     always created the first time it's called.  It takes a time mark array
##     index as an input parameter and does not store a mark if a time mark
##     index is supplied.  In array context, the amount of time between all
##     stored marks is returned.  In scalar context, the time since the last
##     (or supplied) mark index is returned.  Time is always reported in number
##     of seconds.
##   getCommand
##     This subroutine prints the command that was supplied on the command line
##     when the script was executed (plus it adds a command about user defaults
##     that were added) however it does not print any standard input/output
##     redirections.  If a non-zero value is supplied, it also displays the
##     perl path used, using the `which` system command.
##   sglob
##     This subroutine exists for convenience purposes to make it easier to
##     supply a single input file which has spaces in its name, yet also still
##     provides the convenience of glob (which interprets characters such as
##     '*' like the command line does).  If multiple space delimited files are
##     supplied, it is the user's responsibility to escape the space
##     characters.
##   getVersion
##     Returns a software version message.
##   isStandardInputFromTerminal
##     Returns true if *no* input has been redirected into this script, false
##     if there is input on STDIN.
##   isStandardOutputToTerminal
##     Returns true if output is going to a TTY (i.e. output has *not* been
##     redirected on the command line) AND if STDOUT is selected, false if
##     STDOUT is not selected or output is not going to a TTY.
##   quit
##     Makes a call to exit to stop the script unless the --force flag was
##     provided on the command line.  You may supply an exit value, but note
##     that this template uses negative values for template calls to quit.
##   printRunReport
##     This sub prints a report about the running of the script, including
##     total running time, the number of warnings, errors, and debug calls
##     issued, followed by a summary of the types of errors and warnings issued
##     along with the numbers of each.  Use this sub at the end of your script.
##   getFileSets
##     This subroutine is useful if pairs or other multiple combinations of
##     input files must be processed together to produce 1 output file.  You
##     can give this subroutine arrays of files sorted in respective order and
##     it will return groups of corresponding files that are to be processed
##     together.  It will even associate a common individual file with all the
##     files of another type.  See the comments above the subroutine itself for
##     examples of the combinations this subroutine can handle.  This
##     subroutine also predicts over-write scenarios and quits if overwrite
##     situations are detected.  It returns outfile names (or stubs) in
##     addition to input file combinations.
##   transpose
##     This subroutine will transpose a 2 dimensional array.
##   getExistingOutfiles (deprecated)
##     This subroutine will take output file name stubs output by getFileSets
##     and an outfile suffix and return a list of files already existing.
##   mkdirs
##     Creates groups of directories unless in dry run mode.  Not recursive.
##   checkFile
##     This subroutine determines whether an unwanted overwrite will occur and
##     depending on whether the overwrite or skip-existing flags were supplied,
##     returns true/false indicating whether the file may be opened for
##     writing.
##   openIn
##     Opens & tracks input files.  Returns false if there was a problem.
##   closeIn
##     Closes & tracks input files.
##   openOut
##     Opens & tracks output files unless in dry run mode.  Returns false if
##     there was a problem.  Selects the output handle by default.
##   closeOut
##     Closes & tracks output files unless in dry run mode.  Selects STDOUT.
##   copyArray
##     Recursively copies a multi-dimensional array of scalars.
##   getUserDefaults
##     Retrieves default command line parameters the user previously saved.
##   saveUserDefaults
##     Saves any command line parameters in a defaults file.
##   getHeader
##     Returns the standard output file header.
##   GetNextIndepCombo
##     Supply an array reference representing a combination (initially empty)
##     and an array containing ranges of numbers (1-n) to choose from and each
##     call will set the combination array to contain the next in a series of
##     all possible combinations of numbers until exhausted.  E.g. If the
##     ranges are [2,3,1], the combos returned at each call will be ([1,1,1],
##     [1,2,1],[1,3,1],[2,1,1],[2,2,1],[2,3,1]) on each subsequent call.
##   makeStubsUnique
##     Given a 2D array of outfile stubs where each subarray is a combination
##     corresponding to different types of input files, they are checked for
##     uniqueness.  If not unique, to protect against the possibility of
##     overwriting a file, the outfile stub is appended together using a
##     delimiting dot ('.') with either another single unique stub or with all
##     the other stubs.
##   getMatchedSets
##     The purpose of this subroutine is to link different types of ordered
##     input files.  Given a 3D array (an array composed of 2D arrays of
##     different types of strings with differing dimensions), this sub tries to
##     join arrays with common dimensions (transposing them if necessary and
##     duplicating their contents if necessary to create a match).  The
##     partnering 2D arrays are then flattened into partnering combinations,
##     corresponding by position.  Any 2D arrays without common dimensions and
##     unjoined are mixed in all possible combinations and returned.

##
## Initialize Run
##

use warnings;
use strict;
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev);
use File::Glob ':glob';

#Global variables used in subs - DO NOT EDIT
my $preserve_args  = [@ARGV];
my $defaults_dir   = (sglob('~/.rpst'))[0];
my @user_defaults  = getUserDefaults(1);

#Global variables used in subs - VALUE EDIT OK
my $default_stub        = 'STDIN';
my $header              = 1;
my $error_limit_default = 5;
my($output_mode,
   $error_limit,
   $help,
   $extended,
   $version,
   $overwrite,
   $skip_existing,
   $dry_run,
   $verbose,
   $quiet,
   $DEBUG,
   $force,
   $pipeline_mode,
   $use_as_default);

#Global variables used in main - EDIT OK
my($outfile_suffix);
my $input_files    = [];
my $outdirs        = [];

##
## DECLARE VARIABLES HERE
my $files1 = [];
my $files2 = [];
##



#Command line parameters
my $GetOptHash =
  {


   ##
   ## ENTER YOUR COMMAND LINE PARAMETERS HERE AS BELOW
   'j=s' => sub {push(@$files1,
                      [sglob($_[1])])},
   'k=s' => sub {push(@$files2,
                      [sglob($_[1])])},
   ##



   'i|input-file|stdin-stub|stub=s'
			  => sub {push(@$input_files,    #REQUIRED unless <> is
				       [sglob($_[1])])}, #         supplied
   '<>'                   => sub {checkFileOpt($_[0],1);
				  push(@$input_files,    #REQUIRED unless -i is
				       [sglob($_[0])])}, #         supplied
   'o|outfile-suffix=s'   => \$outfile_suffix,           #OPTIONAL [undef]
   'outdir=s'             => sub {push(@$outdirs,        #OPTIONAL [none]
				       [sglob($_[1])])},
   'overwrite+'           => \$overwrite,                #OPTIONAL [Off]
   'skip-existing!'       => \$skip_existing,            #OPTIONAL [Off]
   'force:+'              => \$force,                    #OPTIONAL [Off]
   'verbose:+'            => \$verbose,                  #OPTIONAL [Off]
   'quiet'                => \$quiet,                    #OPTIONAL [Off]
   'debug:+'              => \$DEBUG,                    #OPTIONAL [Off]
   'help'                 => \$help,                     #OPTIONAL [Off]
   'extended'             => \$extended,                 #OPTIONAL [Off]
   'version'              => \$version,                  #OPTIONAL [Off]
   'header!'              => \$header,                   #OPTIONAL [On]
   'error-type-limit=i'   => \$error_limit,              #OPTIONAL [5]
   'dry-run'              => \$dry_run,                  #OPTIONAL [Off]
   'save-as-default'      => \$use_as_default,           #OPTIONAL [Off]
   'output-mode=s'        => \$output_mode,              #OPTIONAL [error]
   'pipeline-mode!'       => \$pipeline_mode,            #OPTIONAL [guess]
  };

#Set user-saved defaults
GetOptionsFromArray([@user_defaults],%$GetOptHash) if(scalar(@user_defaults));

#Get the input options & catch any errors in option parsing
if(!GetOptions(%$GetOptHash))
  {
    #Try to guess which arguments GetOptions is complaining about
    my @possibly_bad = grep {!(-e $_)} map {@$_} @$input_files;

    error('Getopt::Long::GetOptions reported an error while parsing the ',
	  'command line arguments.  The warning should be above.  Please ',
	  'correct the offending argument(s) and try again.');
    usage(1);
    quit(-2);
  }

##
## Validate Options
##

#Process & validate the default options (supply whether there will be outfiles)
processDefaultOptions(defined($outfile_suffix));



##
## VALIDATE COMMAND LINE OPTIONS HERE
##



#Require input file(s)
if(scalar(@$input_files) == 0 && isStandardInputFromTerminal())
  {
    error('No input detected.');
    usage(1);
    quit(-7);
  }

#Require an outfile suffix if an outdir has been supplied
if(scalar(@$outdirs) && !defined($outfile_suffix))
  {
    error("An outfile suffix (-o) is required if an output directory ",
	  "(--outdir) is supplied.  Note, you may supply an empty string ",
	  "to name the output files the same as the input files.");
    quit(-8);
  }

##
## Prepare Input/Output Files
##

#Get input & output files in corresponding sets.  E.g.:
#
#    -i '1 2 3' -d 'a b c'                     #Command line
#    $input_files = [[1,2,3]];
#    $other_files = [[a,b,c]];
#    $input_file_sets = [[1,a],[2,b],[3,c]];   #Resulting sets
#
my($input_file_sets,   #getFileSets(3DinfileArray,2DsuffixArray,2DoutdirArray)
   $output_file_sets) = getFileSets([$input_files,


				     #ENTER INPUT FILE ARRAYS HERE
                                     $files1,
                                     $files2,


				    ],

				    [[$outfile_suffix],


				     #ENTER SUFFIX ARRAYS HERE IN SAME ORDER


				    ],

				    $outdirs);

#Create the output directories
mkdirs(@$outdirs);









##
## ENTER YOUR PRE-FILE-PROCESSING CODE HERE
##









#For each set of corresponding input files
foreach my $set_num (0..$#$input_file_sets)
  {
    my $input_file   =    $input_file_sets->[$set_num]->[0];
    my($output_file) = @{$output_file_sets->[$set_num]->[0]};

    openIn(*INPUT,$input_file)    || next;
    openOut(*OUTPUT,$output_file) || next;

    next if($dry_run);


    ##
    ## BEGIN TEST CODE 1
    ##


##TESTSLUG01



    ##
    ## END TEST CODE 1
    ##



    closeOut(*OUTPUT);
    closeIn(*INPUT);
  }










##
## ENTER YOUR POST-FILE-PROCESSING CODE HERE
##


##
## BEGIN TEST CODE 2
##


##TESTSLUG02


##
## END TEST CODE 2
##










##
## End Main
##

























































































BEGIN
  {
    #This allows us to track runtime warnings about undefined variables, etc.
    $SIG{__WARN__} = sub {my $err = $_[0];chomp($err);
			  warning("Runtime warning: [$err].")};
  }

END
  {
    flushStderrBuffer(1);
  }

##
## Subroutines
##

#Copies all hash arguments' contents from the parameter array into 1 hash.
#All other arguments must be scalars - otherwise generates an error
sub getSubOpts
  {
    my $opts = {};
    foreach my $opthash (grep {defined($_) && ref($_) eq 'HASH'} @_)
      {
	foreach my $optname (keys(%$opthash))
	  {
	    if(exists($opts->{$optname}))
	      {error("Multiple options with the same name: [$optname].  ",
		     "Overwriting.")}
	    $opts->{$optname} = $opthash->{$optname};
	  }
      }

    if(scalar(grep {defined($_) && ref($_) ne 'HASH' && ref($_) ne ''} @_))
      {error("Non-hash and non-scalar arguments encountered.")}

    return($opts);
  }

##
## Subroutine that prints formatted verbose messages.  Specifying a 1 as the
## first argument prints the message in overwrite mode (meaning subsequence
## verbose, error, warning, or debug messages will overwrite the message
## printed here.  However, specifying a hard return as the first character will
## override the status of the last line printed and keep it.  Global variables
## keep track of print length so that previous lines can be cleanly
## overwritten.  Note, this subroutine buffers output until $verbose is defined
## in main.  The buffer will be emptied the first time verbose() is called
## after $verbose has been defined.  The purpose of this is to still output
## verbose messages that were generated before the command line --verbose flag
## has been processed.
##
sub verbose
  {
    if(defined($verbose) && !$verbose)
      {
	flushStderrBuffer() if(defined($main::stderr_buffer));
	return(0);
      }

    #Grab the options from the parameter array
    my $opts           = getSubOpts(@_);
    my $overwrite_flag = (exists($opts->{OVERME}) && defined($opts->{OVERME}) ?
			  $opts->{OVERME} : 0);
    my $message_level  = (exists($opts->{LEVEL}) && defined($opts->{LEVEL}) ?
			  $opts->{LEVEL} : 1);
    my $frequency      =  (exists($opts->{FREQUENCY}) &&
			   defined($opts->{FREQUENCY}) &&
			   $opts->{FREQUENCY} > 0 ? $opts->{FREQUENCY} : 1);

    if($frequency =~ /\./)
      {
	warning("The frequency value: [$frequency] must be an integer (e.g. ",
		"print every 100th line).");
	$frequency = ($frequency < 1 ? 1 : int($frequency));
      }

    #If we're not printing every one of these verbose messages
    if($frequency > 1)
      {
	#Determine what line the verbose call was made from so we can track
	#how many times it has been called
	my(@caller_info,$line_num);
	my $stack_level = 0;
	while(@caller_info = caller($stack_level))
	  {
	    $line_num = $caller_info[2];
	    last if(defined($line_num));
	    $stack_level++;
	  }

	#Initialize the frequency hash to track number of calls from this line
	#of code
	if(!defined($main::verbose_freq_hash))
	  {$main::verbose_freq_hash->{$line_num} = 1}
	else
	  {$main::verbose_freq_hash->{$line_num}++}

	#If the number of calls is evenly divisible by the frequency
	return(0) if($main::verbose_freq_hash->{$line_num} % $frequency != 0);
      }

    #Return if $verbose is greater than a negative level at which this message
    #is printed or if $verbose is less than a positive level at which this
    #message is printed.  Negative levels are for template diagnostics.
    return(0) if(defined($verbose) &&
		 (($message_level < 0 && $verbose > $message_level) ||
		  ($message_level > 0 && $verbose < $message_level)));

    #Grab the message from the parameter array
    my $verbose_message = join('',grep {defined($_) && ref($_) eq ''} @_);

    #Turn on the overwrite flag automatically if carriage returns are found
    $overwrite_flag = 1 if(!$overwrite_flag && $verbose_message =~ /\r/);

    #Initialize globals if not done already
    $main::last_verbose_size  = 0 if(!defined($main::last_verbose_size));
    $main::last_verbose_state = 0 if(!defined($main::last_verbose_state));
    $main::verbose_warning    = 0 if(!defined($main::verbose_warning));

    #Determine the message length
    my($verbose_length);
    if($overwrite_flag)
      {
	$verbose_message =~ s/\r$//;
	if(!$main::verbose_warning && $verbose_message =~ /\n|\t/)
	  {
	    warning('Hard returns and tabs cause overwrite mode to not work ',
		    'properly.');
	    $main::verbose_warning = 1;
	  }
      }
    else
      {chomp($verbose_message)}

    #If this message is not going to be over-written (i.e. we will be printing
    #a \n after this verbose message), we can reset verbose_length to 0 which
    #will cause $main::last_verbose_size to be 0 the next time this is called
    if(!$overwrite_flag)
      {$verbose_length = 0}
    #If there were \r's in the verbose message submitted (after the last \n)
    #Calculate the verbose length as the largest \r-split string
    elsif($verbose_message =~ /\r[^\n]*$/)
      {
	my $tmp_message = $verbose_message;
	$tmp_message =~ s/.*\n//;
	($verbose_length) = sort {$b <=> $a} map {length($_)}
	  split(/\r/,$tmp_message);
      }
    #Otherwise, the verbose_length is the size of the string after the last \n
    elsif($verbose_message =~ /([^\n]*)$/)
      {$verbose_length = length($1)}

    #If the buffer is not being flushed, the verbose output doesn't start with
    #a \n, and output is to the terminal, make sure we don't over-write any
    #STDOUT output
    #NOTE: This will not clean up verbose output over which STDOUT was written.
    #It will only ensure verbose output does not over-write STDOUT output
    #NOTE: This will also break up STDOUT output that would otherwise be on one
    #line, but it's better than over-writing STDOUT output.  If STDOUT is going
    #to the terminal, it's best to turn verbose off.
    if(!$| && $verbose_message !~ /^\n/ && isStandardOutputToTerminal())
      {
	#The number of characters since the last flush (i.e. since the last \n)
	#is the current cursor position minus the cursor position after the
	#last flush (thwarted if user prints \r's in STDOUT)
	#NOTE:
	#  tell(STDOUT) = current cursor position
	#  sysseek(STDOUT,0,1) = cursor position after last flush (or undef)
	my $num_chars = sysseek(STDOUT,0,1);
	if(defined($num_chars))
	  {$num_chars = tell(STDOUT) - $num_chars}
	else
	  {$num_chars = 0}

	#If there have been characters printed since the last \n, prepend a \n
	#to the verbose message so that we do not over-write the user's STDOUT
	#output
	if($num_chars > 0)
	  {$verbose_message = "\n$verbose_message"}
      }

    #Overwrite the previous verbose message by appending spaces just before the
    #first hard return in the verbose message IF THE VERBOSE MESSAGE DOESN'T
    #BEGIN WITH A HARD RETURN.  However note that the length stored as the
    #last_verbose_size is the length of the last line printed in this message.
    if($verbose_message =~ /^([^\n]*)/ && $main::last_verbose_state &&
       $verbose_message !~ /^\n/)
      {
	my $append = ' ' x ($main::last_verbose_size - length($1));
	unless($verbose_message =~ s/\n/$append\n/)
	  {$verbose_message .= $append}
      }

    #If you don't want to overwrite the last verbose message in a series of
    #overwritten verbose messages, you can begin your verbose message with a
    #hard return.  This tells verbose() to not overwrite the last line that was
    #printed in overwrite mode.

    if(defined($verbose))
      {
	#Flush the buffer if it is defined
	flushStderrBuffer() if(defined($main::stderr_buffer));

	#Print the current message to standard error
	print STDERR ($verbose_message,
		      ($overwrite_flag ? "\r" : "\n"));
      }
    else
      {
	#Store the message in the stderr buffer until $verbose has been defined
	#by the command line options (using Getopts::Long)
	push(@{$main::stderr_buffer},
	     ['verbose',
	      $message_level,
	      join('',($verbose_message,
		       ($overwrite_flag ? "\r" : "\n")))]);
      }

    #Record the state
    $main::last_verbose_size  = $verbose_length;
    $main::last_verbose_state = $overwrite_flag;

    #Return success
    return(0);
  }

sub verboseOverMe
  {verbose({OVERME=>1},@_)}

##
## Subroutine that prints errors with a leading program identifier containing a
## trace route back to main to see where all the subroutine calls were from,
## the line number of each call, an error number, and the name of the script
## which generated the error (in case scripts are called via a system call).
## Globals used: $error_limit, $quiet, $verbose, $pipeline_mode
##
sub error
  {
    if(defined($quiet) && $quiet)
      {
	#This will empty the buffer if there's something in it based on $quiet
	flushStderrBuffer() if(defined($main::stderr_buffer));
	return(0);
      }

    if(!defined($pipeline_mode))
      {$pipeline_mode = inPipeline()}

    #Gather and concatenate the error message and split on hard returns
    my @error_message = split(/\n/,join('',grep {defined($_)} @_));
    push(@error_message,'') unless(scalar(@error_message));
    pop(@error_message) if(scalar(@error_message) > 1 &&
			   $error_message[-1] !~ /\S/);

    $main::error_number++;
    my $leader_string = "ERROR$main::error_number:";

    #Assign the values from the calling subroutines/main
    my(@caller_info,$line_num,$caller_string,$stack_level,$script);

    #Build a trace-back string.  This will be used for tracking the number of
    #each type of error as well as embedding into the error message in debug
    #mode.
    $script = $0;
    $script =~ s/^.*\/([^\/]+)$/$1/;
    @caller_info = caller(0);
    $line_num = $caller_info[2];
    $caller_string = '';
    $stack_level = 1;
    while(@caller_info = caller($stack_level))
      {
	my $calling_sub = $caller_info[3];
	$calling_sub =~ s/^.*?::(.+)$/$1/ if(defined($calling_sub));
	$calling_sub = (defined($calling_sub) ? $calling_sub : 'MAIN');
	$caller_string .= "$calling_sub(LINE$line_num):"
	  if(defined($line_num));
	$line_num = $caller_info[2];
	$stack_level++;
      }
    $caller_string .= "MAIN(LINE$line_num):";

    #If $DEBUG hasn't been defined or is true, or we're in a pipeline,
    #prepend a call-trace
    if(!defined($DEBUG) || $DEBUG || $pipeline_mode)
      {
	$leader_string .= "$script:";
	if(!defined($DEBUG) || $DEBUG)
	  {$leader_string .= $caller_string}
      }

    $leader_string .= ' ';
    my $leader_length = length($leader_string);

    #Figure out the length of the first line of the error
    my $error_length = length(($error_message[0] =~ /\S/ ?
			       $leader_string : '') .
			      $error_message[0]);

    #Clean up any previous verboseOverMe output that may be longer than the
    #first line of the error message, put leader string at the beginning of
    #each line of the message, and indent each subsequent line by the length
    #of the leader string
    my $error_string = $leader_string . shift(@error_message) .
      (defined($verbose) && $verbose && defined($main::last_verbose_state) &&
       $main::last_verbose_state ?
       ' ' x ($main::last_verbose_size - $error_length) : '') . "\n";
    foreach my $line (@error_message)
      {$error_string .= (' ' x $leader_length) . $line . "\n"}

    #If the global error hash does not yet exist, store the first example of
    #this error type
    if(!defined($main::error_hash) ||
       !exists($main::error_hash->{$caller_string}))
      {
	$main::error_hash->{$caller_string}->{EXAMPLE}    = $error_string;
	$main::error_hash->{$caller_string}->{EXAMPLENUM} =
	  $main::error_number;

	$main::error_hash->{$caller_string}->{EXAMPLE} =~ s/\n */ /g;
	$main::error_hash->{$caller_string}->{EXAMPLE} =~ s/ $//g;
	$main::error_hash->{$caller_string}->{EXAMPLE} =~ s/^(.{100}).+/$1.../;
      }

    #Increment the count for this error type
    $main::error_hash->{$caller_string}->{NUM}++;

    #Flush the buffer if it is defined and either quiet is defined and true or
    #defined, false, and error_limit is defined
    flushStderrBuffer() if((defined($quiet) &&
			    ($quiet || defined($error_limit))) &&
			   defined($main::stderr_buffer));

    #Print the error unless it is over the limit for its type
    if(!defined($error_limit) || $error_limit == 0 ||
       $main::error_hash->{$caller_string}->{NUM} <= $error_limit)
      {
	#Let the user know if we're going to start suppressing errors of
	#this type
	if(defined($error_limit) && $error_limit &&
	   $main::error_hash->{$caller_string}->{NUM} == $error_limit)
	  {
	    $error_string .=
	      join('',($leader_string,"NOTE: Further errors of this ",
		       "type will be suppressed.\n$leader_string",
		       "Set --error-type-limit to 0 to turn off error ",
		       "suppression\n"));
	  }

	if(defined($quiet))
	  {
	    #The following assumes we'd not have gotten here if quiet was true
	    print STDERR ($error_string);
	  }
	else
	  {
	    #Store the message in the stderr buffer until $quiet has been
	    #defined by the command line options (using Getopts::Long)
	    push(@{$main::stderr_buffer},
		 ['error',
		  $main::error_hash->{$caller_string}->{NUM},
		  $error_string,
		  $leader_string]);
	  }
      }

    #Reset the verbose states if verbose is true
    if(defined($verbose) && $verbose)
      {
	$main::last_verbose_size  = 0;
	$main::last_verbose_state = 0;
      }

    #Return success
    return(0);
  }

##
## Subroutine that prints warnings with a leader string containing a warning
## number
##
## Globals used: $error_limit, $quiet, $verbose, $pipeline_mode
##
sub warning
  {
    if(defined($quiet) && $quiet)
      {
	#This will empty the buffer if there's something in it based on $quiet
	flushStderrBuffer() if(defined($main::stderr_buffer));
	return(0);
      }

    if(!defined($pipeline_mode))
      {$pipeline_mode = inPipeline()}

    $main::warning_number++;

    #Gather and concatenate the warning message and split on hard returns
    my @warning_message = split(/\n/,join('',grep {defined($_)} @_));
    push(@warning_message,'') unless(scalar(@warning_message));
    pop(@warning_message) if(scalar(@warning_message) > 1 &&
			     $warning_message[-1] !~ /\S/);

    my $leader_string = "WARNING$main::warning_number:";

    #Assign the values from the calling subroutines/main
    my(@caller_info,$line_num,$caller_string,$stack_level,$script);

    #Build a trace-back string.  This will be used for tracking the number of
    #each type of warning as well as embedding into the warning message in
    #debug mode.
    $script = $0;
    $script =~ s/^.*\/([^\/]+)$/$1/;
    @caller_info = caller(0);
    $line_num = $caller_info[2];
    $caller_string = '';
    $stack_level = 1;
    while(@caller_info = caller($stack_level))
      {
	my $calling_sub = $caller_info[3];
	$calling_sub =~ s/^.*?::(.+)$/$1/ if(defined($calling_sub));
	$calling_sub = (defined($calling_sub) ? $calling_sub : 'MAIN');
	$caller_string .= "$calling_sub(LINE$line_num):"
	  if(defined($line_num));
	$line_num = $caller_info[2];
	$stack_level++;
      }
    $caller_string .= "MAIN(LINE$line_num):";

    #If $DEBUG hasn't been defined or is true, or we're in a pipeline,
    #prepend a call-trace
    if(!defined($DEBUG) || $DEBUG || $pipeline_mode)
      {
	$leader_string .= "$script:";
	if(!defined($DEBUG) || $DEBUG)
	  {$leader_string .= $caller_string}
      }

    $leader_string   .= ' ';
    my $leader_length = length($leader_string);

    #Figure out the length of the first line of the error
    my $warning_length = length(($warning_message[0] =~ /\S/ ?
				 $leader_string : '') .
				$warning_message[0]);

    #Clean up any previous verboseOverMe output that may be longer than the
    #first line of the warning message, put leader string at the beginning of
    #each line of the message and indent each subsequent line by the length
    #of the leader string
    my $warning_string =
      $leader_string . shift(@warning_message) .
	(defined($verbose) && $verbose && defined($main::last_verbose_state) &&
	 $main::last_verbose_state ?
	 ' ' x ($main::last_verbose_size - $warning_length) : '') .
	   "\n";
    foreach my $line (@warning_message)
      {$warning_string .= (' ' x $leader_length) . $line . "\n"}

    #If the global warning hash does not yet exist, store the first example of
    #this warning type
    if(!defined($main::warning_hash) ||
       !exists($main::warning_hash->{$caller_string}))
      {
	$main::warning_hash->{$caller_string}->{EXAMPLE}    = $warning_string;
	$main::warning_hash->{$caller_string}->{EXAMPLENUM} =
	  $main::warning_number;

	$main::warning_hash->{$caller_string}->{EXAMPLE} =~ s/\n */ /g;
	$main::warning_hash->{$caller_string}->{EXAMPLE} =~ s/ $//g;
	$main::warning_hash->{$caller_string}->{EXAMPLE} =~
	  s/^(.{100}).+/$1.../;
      }

    #Increment the count for this warning type
    $main::warning_hash->{$caller_string}->{NUM}++;

    #Flush the buffer if it is defined and either quiet is defined and true or
    #defined, false, and error_limit is defined
    flushStderrBuffer() if((defined($quiet) &&
			    ($quiet || defined($error_limit))) &&
			   defined($main::stderr_buffer));

    #Print the warning unless it is over the limit for its type
    if(!defined($error_limit) || $error_limit == 0 ||
       $main::warning_hash->{$caller_string}->{NUM} <= $error_limit)
      {
	#Let the user know if we're going to start suppressing errors of
	#this type
	if(defined($error_limit) && $error_limit &&
	   $main::warning_hash->{$caller_string}->{NUM} == $error_limit)
	  {
	    $warning_string .=
	      join('',($leader_string,"NOTE: Further warnings of this ",
		       "type will be suppressed.\n$leader_string",
		       "Set --error-type-limit to 0 to turn off error ",
		       "suppression\n"));
	  }

	if(defined($quiet))
	  {
	    #The following assumes we'd not have gotten here if quiet was true
	    print STDERR ($warning_string);
	  }
	else
	  {
	    #Store the message in the stderr buffer until $quiet has been
	    #defined by the command line options (using Getopts::Long)
	    push(@{$main::stderr_buffer},
		 ['warning',
		  $main::warning_hash->{$caller_string}->{NUM},
		  $warning_string,
		  $leader_string]);
	  }
      }

    #Reset the verbose states if verbose is true
    if(defined($verbose) && $verbose)
      {
	$main::last_verbose_size  = 0;
	$main::last_verbose_state = 0;
      }

    #Return success
    return(0);
  }

##
## Subroutine that gets a line of input and accounts for carriage returns that
## many different platforms use instead of hard returns.  Note, it uses a
## global array reference variable ($infile_line_buffer) to keep track of
## buffered lines from multiple file handles.
##
sub getLine
  {
    my $file_handle = $_[0];

    #Set a global array variable if not already set
    $main::infile_line_buffer = {} if(!defined($main::infile_line_buffer));
    if(!exists($main::infile_line_buffer->{$file_handle}))
      {$main::infile_line_buffer->{$file_handle}->{FILE} = []}

    #If this sub was called in array context
    if(wantarray)
      {
	#Check to see if this file handle has anything remaining in its buffer
	#and if so return it with the rest
	if(scalar(@{$main::infile_line_buffer->{$file_handle}->{FILE}}) > 0)
	  {
	    return(@{$main::infile_line_buffer->{$file_handle}->{FILE}},
		   map
		   {
		     #If carriage returns were substituted and we haven't
		     #already issued a carriage return warning for this file
		     #handle
		     if(s/\r\n|\n\r|\r/\n/g &&
			!exists($main::infile_line_buffer->{$file_handle}
				->{WARNED}))
		       {
			 $main::infile_line_buffer->{$file_handle}->{WARNED}
			   = 1;
			 warning('Carriage returns were found in your file ',
				 'and replaced with hard returns.');
		       }
		     split(/(?<=\n)/,$_);
		   } <$file_handle>);
	  }
	
	#Otherwise return everything else
	return(map
	       {
		 #If carriage returns were substituted and we haven't already
		 #issued a carriage return warning for this file handle
		 if(s/\r\n|\n\r|\r/\n/g &&
		    !exists($main::infile_line_buffer->{$file_handle}
			    ->{WARNED}))
		   {
		     $main::infile_line_buffer->{$file_handle}->{WARNED}
		       = 1;
		     warning('Carriage returns were found in your file ',
			     'and replaced with hard returns.');
		   }
		 split(/(?<=\n)/,$_);
	       } <$file_handle>);
      }

    #If the file handle's buffer is empty, put more on
    if(scalar(@{$main::infile_line_buffer->{$file_handle}->{FILE}}) == 0)
      {
	my $line = <$file_handle>;
	#The following is to deal with files that have the eof character at the
	#end of the last line.  I may not have it completely right yet.
	if(defined($line))
	  {
	    if($line =~ s/\r\n|\n\r|\r/\n/g &&
	       !exists($main::infile_line_buffer->{$file_handle}->{WARNED}))
	      {
		$main::infile_line_buffer->{$file_handle}->{WARNED} = 1;
		warning('Carriage returns were found in your file and ',
			'replaced with hard returns.');
	      }
	    @{$main::infile_line_buffer->{$file_handle}->{FILE}} =
	      split(/(?<=\n)/,$line);
	  }
	else
	  {@{$main::infile_line_buffer->{$file_handle}->{FILE}} = ($line)}
      }

    #Shift off and return the first thing in the buffer for this file handle
    return($_ = shift(@{$main::infile_line_buffer->{$file_handle}->{FILE}}));
  }

##
## This subroutine allows the user to print debug messages containing the line
## of code where the debug print came from and a debug number.  Debug prints
## will only be printed (to STDERR) if the debug option is supplied on the
## command line.
##
sub debug
  {
    if(defined($DEBUG) && !$DEBUG)
      {
	flushStderrBuffer() if(defined($main::stderr_buffer));
	return(0);
      }

    #Grab the options from the parameter array
    my $opts           = getSubOpts(@_);
    my $message_level  = (exists($opts->{LEVEL}) && defined($opts->{LEVEL}) ?
			  $opts->{LEVEL} : 1);

    #Return if $DEBUG level is greater than a negative message level at which
    #this message is printed or if $DEBUG level is less than a positive message
    #level at which this message is printed.  Negative levels are for template
    #diagnostics.
    return(0) if(defined($DEBUG) &&
		 (($message_level < 0 && $DEBUG > $message_level) ||
		  ($message_level > 0 && $DEBUG < $message_level)));

    $main::debug_number++;

    #Gather and concatenate the error message and split on hard returns
    my @debug_message =
      split(/\n/,join('',grep {defined($_) && ref($_) eq ''} @_));
    push(@debug_message,'') unless(scalar(@debug_message));
    pop(@debug_message) if(scalar(@debug_message) > 1 &&
			   $debug_message[-1] !~ /\S/);

    my $leader_string = "DEBUG$main::debug_number:";

    #Assign the values from the calling subroutines/main
    my(@caller_info,$line_num,$caller_string,$stack_level,$script);

    #Build a trace-back string.
    $script = $0;
    $script =~ s/^.*\/([^\/]+)$/$1/;

    if(!defined($pipeline_mode) || $pipeline_mode)
      {$leader_string .= "$script:"}

    @caller_info = caller(0);
    $line_num = $caller_info[2];
    $caller_string = '';
    $stack_level = 1;
    while(@caller_info = caller($stack_level))
      {
	my $calling_sub = $caller_info[3];
	$calling_sub =~ s/^.*?::(.+)$/$1/ if(defined($calling_sub));
	$calling_sub = (defined($calling_sub) ? $calling_sub : 'MAIN');
	$caller_string .= "$calling_sub(LINE$line_num):"
	  if(defined($line_num));
	$line_num = $caller_info[2];
	$stack_level++;
      }
    $caller_string .= "MAIN(LINE$line_num): ";
    $caller_string =~ s/:.*/:/;
    $leader_string .= $caller_string;

    #Figure out the length of the first line of the error
    my $debug_length = length(($debug_message[0] =~ /\S/ ?
			       $leader_string : '') .
			      $debug_message[0]);

    #Contstruct the debug message string
    #The first line should contain a trace and clean up verbose-over-me stuff
    my $debug_str =
      join('',($leader_string,
	       shift(@debug_message),
	       (defined($verbose) && $verbose &&
		defined($main::last_verbose_state) &&
		$main::last_verbose_state ?
		' ' x ($main::last_verbose_size - $debug_length) : ''),
	       "\n"));
    #Subsequent lines will be indented by the length of the leader string
    my $leader_length = length($leader_string);
    foreach my $line (@debug_message)
      {$debug_str .= (' ' x $leader_length) . $line . "\n"}

    if(defined($DEBUG))
      {
	flushStderrBuffer() if(defined($main::stderr_buffer));

	print STDERR ($debug_str);
      }
    else
      {
	#Store the message in the stderr buffer until $quiet has been
	#defined by the command line options (using Getopts::Long)
	push(@{$main::stderr_buffer},['debug',$message_level,$debug_str]);
      }

    #Reset the verbose states if verbose is true
    if(defined($verbose) && $verbose)
      {
	$main::last_verbose_size = 0;
	$main::last_verbose_state = 0;
      }

    #Return success
    return(0);
  }

##
## This sub marks the time (which it pushes onto an array) and in scalar
## context returns the time since the last mark by default or supplied mark
## (optional) In array context, if an index is not supplied, the time between
## all marks is returned.
## A mark is not made if a mark index is supplied
## Uses a global time_marks array reference
##
sub markTime
  {
    #Record the time
    my $time = time();

    #Set a global array variable if not already set to contain (as the first
    #element) the time the program started (NOTE: "$^T" is a perl variable that
    #contains the start time of the script)
    $main::time_marks = [$^T] if(!defined($main::time_marks));

    #Read in the time mark index or set the default value
    my $mark_index = (defined($_[0]) ? $_[0] : -1);  #Optional Default: -1

    #Error check the time mark index sent in
    if($mark_index > (scalar(@$main::time_marks) - 1))
      {
	error('Supplied time mark index is larger than the size of the ',
	      "time_marks array.\nThe last mark will be set.");
	$mark_index = -1;
      }

    #Calculate the time since the time recorded at the time mark index
    my $time_since_mark = $time - $main::time_marks->[$mark_index];

    #Add the current time to the time marks array
    push(@$main::time_marks,$time)
      if(!defined($_[0]) || scalar(@$main::time_marks) == 0);

    #Return the time since the time recorded at the supplied time mark index
    return($time_since_mark);
  }

##
## This subroutine reconstructs the command entered on the command line
## (excluding standard input and output redirects).  The intended use for this
## subroutine is for when a user wants the output to contain the input command
## parameters in order to keep track of what parameters go with which output
## files.
##
#Globals used: $preserve_args
sub getCommand
  {
    my $perl_path_flag = $_[0];
    my $no_defaults    = $_[1];
    my($command);
    my @return_args = ();

    #Determine the script name
    my $script = $0;
    $script =~ s/^.*\/([^\/]+)$/$1/;

    #Put quotes around any parameters containing un-escaped spaces or asterisks
    my $arguments = defined($preserve_args) ? [@$preserve_args] : [];
    foreach my $arg (@$arguments)
      {if($arg =~ /(?<!\\)[\s\*]/ || $arg =~ /^<|>|\|(?!\|)/ || $arg eq '' ||
	  $arg =~ /[\{\}\[\]\(\)]/)
	 {$arg = "'" . $arg . "'"}}

    #Determine the perl path used (dependent on the `which` unix built-in)
    if($perl_path_flag)
      {
	$command = `which $^X`;
	push(@return_args,$command);
	chomp($command);
	$command .= ' ';
      }

    #Build the original command
    $command .= join(' ',($0,@$arguments));
    push(@return_args,($0,@$arguments));

    #Add any default flags that were previously saved
    my @default_options = getUserDefaults();
    if(!$no_defaults && scalar(@default_options))
      {
	$command .= ' -- [USER DEFAULTS ADDED: ';
	$command .= join(' ',@default_options);
	$command .= ']';
	push(@return_args,@default_options);
      }

    return(wantarray ? @return_args : $command);
  }

##
## This subroutine performs a more reliable glob than perl's built-in, which
## fails for files with spaces in the name, even if they are escaped.  The
## purpose is to allow the user to enter input files using double quotes and
## un-escaped spaces as is expected to work with many programs which accept
## individual files as opposed to sets of files.  If the user wants to enter
## multiple files, it is assumed that space delimiting will prompt the user to
## realize they need to escape the spaces in the file names.  This version
## works with a mix of unescaped and escaped spaces, as well as glob
## characters.  It will also split non-files on unescaped spaces and uses a
## helper sub (globCurlyBraces) to mitigate truncations from long strings.
##
sub sglob
  {
    #Convert possible 'Getopt::Long::CallBack' to SCALAR by wrapping in quotes:
    my $command_line_string = "$_[0]";
    if(!defined($command_line_string))
      {
	warning("Undefined command line string encountered.");
	return($command_line_string);
      }
    #The command_line_string is 1 existing file (possibly w/ unescaped spaces)
    elsif(-e $command_line_string)
      {
	debug({LEVEL => 2},
	      "Returning argument string: [($command_line_string)].");
	return($command_line_string);
      }
    #Else if the string contains unescaped spaces and does not contain escaped
    #spaces, see if it's a single file (possibly with glob characters)
    elsif($command_line_string =~ /(?<!\\) / &&
	  $command_line_string !~ /\\ /)
      {
	my $x = [bsd_glob($command_line_string,GLOB_CSH)];

	#If glob didn't truncate a pattern, there were multiple things returned
	#or there was 1 thing returned that exists
	if(notAGlobTruncation($command_line_string,$x) &&
	   scalar(@$x) > 1 || ((scalar(@$x) == 1 && -e $x->[0])))
	  {
	    debug({LEVEL => 2},
		  "Returning files with spaces: [(@$x)].");
	    return(@$x);
	  }
      }

    #Expand the string from the command line based on the '{X,Y,...}'
    #pattern...  Explanation:

    #Sometimes, the glob string is larger than GLOB_LIMIT (even though
    #the shell sent in the long string to begin with).  When that
    #happens, bsd_glob just silently chops off everything except the
    #directory, so we will split the strings up here in perl (to expand
    #any '{X,Y,...}' patterns) before passing them to bsd_glob.  This
    #will hopefully shorten each individual file string for bsd_glob to
    #be able to handle.  We'll sort them too to be on the safe side.
    #Since doing this will break filenames/paths that have spaces in them,
    #we'll only do it if there are more than 1024 non-white-space characters in
    #a row.  It would be nice to handle escaped spaces too, but se la vie.
    my @partials = ($command_line_string !~ /\S{1025}/ ?

		    split(/(?<!\\)\s+/,$command_line_string) :

		    map {sort {$a cmp $b} globCurlyBraces($_)}
		    split(/(?<!\\)\s+/,$command_line_string));

    debug({LEVEL => -5},"Partials being sent to bsd_glob: [",
	  join(',',@partials),"].");

    #Note, when bsd_glob gets a string with a glob character it can't expand,
    #it drops the string entirely.  Those strings are returned with the glob
    #characters so the surrounding script can report an error.  The GLOB_ERR
    #posix flag is not used because of the way the patterns are manipulated
    #before getting to bsd_glob - which could cause a valid expansion to
    #nothing that bsd_glob would complain about.
    my @arguments =
      map
	{
	  #Expand the string from the command line using a glob
	  my $v = $_;
	  my $x = [bsd_glob($v,GLOB_CSH)];
	  #If the expansion didn't truncate a file glob pattern to a directory
	  if(notAGlobTruncation($v,$x))
	    {
	      debug({LEVEL => -5},"Not a glob truncation: [$v] -> [@$x].");
	      @$x;
	    }
	  else
	    {
	      debug({LEVEL => -5},"Is a glob truncation: [$v] -> [@$x].");
	      $v;
	    }
	} @partials;

    debug({LEVEL => 2},
	  "Returning split args: [(",join('),(',@arguments),
	  ")] parsed from string: [$command_line_string].");

    #Return the split arguments.  We're assuming that if the command line
    #string was a real file, it would not get here.
    return(@arguments);
  }

#This subroutine takes a string and the result of calling bsd_glob on it and
#determines whether the expansion was successful or whether glob truncated the
#file name leaving just the directory.
sub notAGlobTruncation
  {
    my $preproc_str    = $_[0];
    my $expanded_array = $_[1];

    return(scalar(@$expanded_array) > 1 ||

	   (#There's only 1 expanded result and neither exists
	    scalar(@$expanded_array) == 1 && !-e $expanded_array->[0] &&
	    !-e $preproc_str) ||

	   (#There's only 1 expanded and existing result AND
	    scalar(@$expanded_array) == 1 && -e $expanded_array->[0] &&

	    #If the glob string was too long, everything after the last
	    #directory can be truncated, so we want to avoid returning
	    #that truncated value, thus...

	    (#The expanded value is not a directory OR
	     !-d $expanded_array->[0] ||

	     #Assumed: it is a directory and...

	     (#The pre-expanded value was a valid directory string already
	      #or ended with a slash (implying the dir had glob characters
	      #in its name/path) or the last expanded string's character
	      #is not a slash (implying the end of a pattern wasn't
	      #chopped off by bsd_glob, which would leave a slash).
	      -d $preproc_str || $preproc_str =~ m%/$% ||
	      $expanded_array->[0] !~ m%/$%))));
  }

sub globCurlyBraces
  {
    my $nospace_string = $_[0];

    if($nospace_string =~ /(?<!\\)\s+/)
      {
	error("Unescaped spaces found in input string: [$nospace_string].");
	return($nospace_string);
      }
    elsif(scalar(@_) > 1)
      {
	error("Too many [",scalar(@_),"] parameters sent in.  Expected 1.");
	return(@_);
      }

    #Keep updating an array to be the expansion of a file pattern to
    #separate files
    my @expanded = ($nospace_string);

    #If there exists a '{X,Y,...}' pattern in the string
    if($nospace_string =~ /\{[^\{\}]+\}/)
      {
	#While the first element still has a '{X,Y,...}' pattern
	#(assuming everything else has the same pattern structure)
	while($expanded[0] =~ /\{[^\{\}]+\}/)
	  {
	    #Accumulate replaced file patterns in @g
	    my @buffer = ();
	    foreach my $str (@expanded)
	      {
		#If there's a '{X,Y,...}' pattern, split on ','
		if($str =~ /\{([^\{\}]+)\}/)
		  {
		    my $substr     = $1;
		    my $before     = $`;
		    my $after      = $';
		    my @expansions = split(/,/,$substr);
		    push(@buffer,map {$before . $_ . $after} @expansions);
		  }
		#Otherwise, push on the whole string
		else
		  {push(@buffer,$str)}
	      }

	    #Reset @f with the newly expanded file strings so that we
	    #can handle additional '{X,Y,...}' patterns
	    @expanded = @buffer;
	  }
      }

    #Pass the newly expanded file strings through
    return(wantarray ? @expanded : [@expanded]);
  }

#Globals used: $software_version_number, $created_on_date
sub getVersion
  {
    my $version_message   = '';
    my $template_version  = 3.9;
    my $script            = $0;
    $script               =~ s/^.*\/([^\/]+)$/$1/;
    my $lmd               = localtime((stat($0))[9]);

    if(!defined($software_version_number) || $software_version_number !~ /\S/)
      {
	warning("Software version number variable unset/missing.");
	$software_version_number = 'unknown';
      }

    if((!defined($created_on_date) || $created_on_date eq 'DATE HERE') &&
       $0 !~ /perl_script_template\.pl$/)
      {
	warning("Created-on-date global variable unset/missing.");
	$created_on_date = 'unknown';
      }

    #Create version string
    $version_message  = '#' . join("\n#",
				   ("$script Version $software_version_number",
				    " Created: $created_on_date",
				    " Last modified: $lmd"));

    #Add template version
    $version_message .= "\n#" .
      join("\n#",
	   ('Generated using perl_script_template.pl ' .
	    "Version $template_version",
	    ' Created: 5/8/2006',
	    ' Author:  Robert W. Leach',
	    ' Contact: rleach@genomics.princeton.edu',
	    ' Company: Princeton University',
	    ' Copyright 2015'));

    return($version_message);
  }

#This subroutine is a check to see if input is user-entered via a TTY (result
#is non-zero) or directed in (result is zero)
sub isStandardInputFromTerminal
  {return(-t STDIN || eof(STDIN))}

#This subroutine is a check to see if prints are going to a TTY.  Note,
#explicit prints to STDOUT when another output handle is selected are not
#considered and may defeat this subroutine.
sub isStandardOutputToTerminal
  {return(-t STDOUT && select() eq 'main::STDOUT')}

#This subroutine exits the current process.  Note, you must clean up after
#yourself before calling this.  Does not exit if $force is true.  Takes the
#error number to supply to exit().
sub quit
  {
    my $errno = $_[0];

    if(!defined($errno))
      {$errno = -1}
    elsif($errno !~ /^[+\-]?\d+$/)
      {
	error("Invalid argument: [$errno].  Only integers are accepted.  Use ",
	      "error() or warn() to supply a message, then call quit() with ",
	      "an error number.");
	$errno = -1;
      }

    debug("Exit status: [$errno].");

    printRunReport();

    #Force-flush the buffers before quitting
    flushStderrBuffer(1);

    #Exit if there were no errors or we are not in force mode or (we are in
    #force mode and the error is -1 (meaning an overwrite situation))
    exit($errno) if($errno == 0 || !defined($force) || !$force ||
		    (defined($force) && $force && $errno == -1));
  }

#Generates/prints a report only if we're not in quiet mode and either we're in
#verbose mode, we're in debug mode, there was an error, or there was a warning.
#If $verbose is not defined and (local_quiet wasn't supplied as a parameter,
#we're not in debug mode, there were no errors, and there were no warnings), no
#report will be generated, nor is the report buffered (since this message can
#be considered a part of the warning/error output or verbose output).  If
#$quiet is not defined in main, it will be assumed to be false.
#Globals used: $quiet, $verbose, $DEBUG
sub printRunReport
  {
    my $local_verbose  = $_[0];
    my $global_verbose = defined($verbose) ? $verbose : 0;
    my $global_quiet   = defined($quiet)   ? $quiet   : 0;
    my $global_debug   = defined($DEBUG)   ? $DEBUG   : 0;

    #Return if quiet or there's nothing to report
    return(0) if($global_quiet || (!$global_verbose && !$global_debug &&
				   !defined($main::error_number) &&
				   !defined($main::warning_number)));

    #Before printing a message saying to scroll up for error details, force-
    #flush the stderr buffer
    flushStderrBuffer(1);

    #Report the number of errors, warnings, and debugs on STDERR
    print STDERR ("\n",'Done.  EXIT STATUS: [',
		  'ERRORS: ',
		  ($main::error_number ? $main::error_number : 0),' ',
		  'WARNINGS: ',
		  ($main::warning_number ? $main::warning_number : 0),
		  ($global_debug ?
		   ' DEBUGS: ' .
		   ($main::debug_number ? $main::debug_number : 0) : ''),' ',
		  'TIME: ',markTime(0),"s]");

    #Print an extended report if requested or there was an error or warning
    if($global_verbose || $local_verbose ||
       defined($main::error_number) ||
       defined($main::warning_number))
      {
	if($main::error_number || $main::warning_number)
	  {print STDERR " SUMMARY:\n"}
	else
	  {print STDERR "\n"}

	#If there were errors
	if($main::error_number)
	  {
	    foreach my $err_type
	      (sort {$main::error_hash->{$a}->{EXAMPLENUM} <=>
		       $main::error_hash->{$b}->{EXAMPLENUM}}
	       keys(%$main::error_hash))
	      {print STDERR ("\t",$main::error_hash->{$err_type}->{NUM},
			     " ERROR",
			     ($main::error_hash->{$err_type}->{NUM} > 1 ?
			      'S' : '')," LIKE: [",
			     $main::error_hash->{$err_type}->{EXAMPLE},"]\n")}
	  }

	#If there were warnings
	if($main::warning_number)
	  {
	    foreach my $warn_type
	      (sort {$main::warning_hash->{$a}->{EXAMPLENUM} <=>
		       $main::warning_hash->{$b}->{EXAMPLENUM}}
	       keys(%$main::warning_hash))
	      {print STDERR ("\t",$main::warning_hash->{$warn_type}->{NUM},
			     " WARNING",
			     ($main::warning_hash->{$warn_type}->{NUM} > 1 ?
			      'S' : '')," LIKE: [",
			     $main::warning_hash->{$warn_type}->{EXAMPLE},
			     "]\n")}
	  }

        if(defined($main::error_number) || defined($main::warning_number))
          {print STDERR ("\tScroll up to inspect full errors/warnings ",
		         "in-place.\n")}
      }
    else
      {print STDERR "\n"}
  }


#This subroutine takes multiple "types" of "sets of input files" in a 3D array
#and returns an array of combination arrays where a combination contains 1 file
#of each type.  The best way to explain the associations is by example.  Here
#are example input file associations without output suffixes or directories.
#Each type is a 2D array contained in the outer type array:

#Example 1:
#input files of type 1: [[1,2,3],[a,b,c]]
#input files of type 2: [[4,5,6],[d,e,f]]
#input files of type 3: [[x,y]]
#resulting associations: [[1,4,x],[2,5,x],[3,6,x],[a,d,y],[b,e,y],[c,f,y]]
#Example 2:
#input files of type 1: [[1,2,3],[a,b,c]]
#input files of type 2: [[4,5,6],[d,e,f]]
#input files of type 3: [[x,y,z]]
#resulting associations: [[1,4,x],[2,5,y],[3,6,z],[a,d,x],[b,e,y],[c,f,z]]
#Example 3:
#input files of type 1: [[1,2,3],[a,b,c]]
#input files of type 2: [[4,5,6],[d,e,f]]
#input files of type 3: [[x],[y]]
#resulting associations: [[1,4,x],[2,5,x],[3,6,x],[a,d,y],[b,e,y],[c,f,y]]
#Example 4:
#input files of type 1: [[1,2,3],[a,b,c]]
#input files of type 2: [[4,5,6],[d,e,f]]
#input files of type 3: [[x],[y],[z]]
#resulting associations: [[1,4,x],[2,5,y],[3,6,z],[a,d,x],[b,e,y],[c,f,z]]
#Example 5:
#input files of type 1: [[1,a],[2,b],[3,c]]
#input files of type 2: [[4,d],[5,e],[6,f]]
#input files of type 3: [[x],[y],[z]]
#resulting associations: [[1,4,x],[2,5,y],[3,6,z],[a,d,x],[b,e,y],[c,f,z]]
#Example 6:
#input files of type 1: [[1],[2]]
#input files of type 2: [[a]]
#resulting associations: [[1,a],[2,a]]

#If you submit a 2D array or 1D array, or even a single string, the subroutine
#will wrap it up into a 3D array for processing.  Note that a 1D array mixed
#with 2D arrays will prompt the subroutine to guess which way to associate that
#series of files in the 1D array(s) with the rest.
#The dimensions of the 2D arrays are treated differently if they are the same
#as when they are different.  First, the subroutine will attempt to match array
#dimensions by transposing (and if a dimension is 1, it will copy elements to
#fill it up to match).  For example, the subroutine detects that the second
#dimension in this example matches, so it will copy the 1D array:

#From this:
#input files of type 1: [[1,2],[a,b]]
#input files of type 2: [[4,5],[d,e]]
#input files of type 3: [[x,y]]       #[x,y] will be copied to match dimensions
#To this:
#input files of type 1: [[1,2],[a,b]]
#input files of type 2: [[4,5],[d,e]]
#input files of type 3: [[x,y],[x,y]]
#resulting associations: [[1,4,x],[2,5,y],[a,d,x],[b,e,y]]

#There are also 2 other optional inputs for creating the second return value
#(an array of output file stubs/names associated with each input file).  The
#two optional inputs are a 1D array of outfile suffixes and a 2D array of
#output directories.

#Associations between output directories will be made in the same way as
#between different input file types.  For example, when suffixes are provided
#for type 1:

#Example 1:
#input files of type 1: [[1,2,3],[a,b,c]]
#input files of type 2: [[4,5,6],[d,e,f]]
#outfile suffixes: [.txt,.tab]
#resulting input file associations: [[1,4],[2,5],[3,6],[a,d],[b,e],[c,f]]
#resulting outfile names:  [[1.txt,4.tab],[2.txt,5.tab],[3.txt,6.tab],
#                           [a.txt,d.tab],[b.txt,e.tab],[c.txt,f.tab]]

#Output directories are associated with combinations of files as if the output
#directory 2D array was another file type.  However, the most common expected
#usage is that all output will go to a single directory, so here's an example
#where only the first input file type generates an output file and all output
#goes to a single output directory:

#input files of type 1: [[1,2,3],[a,b,c]]
#input files of type 2: [[4,5,6],[d,e,f]]
#outfile suffixes: [.txt]
#output directories: [[out]]
#resulting input file associations: [[1,4],[2,5],[3,6],[a,d],[b,e],[c,f]]
#resulting outfile names:  [[1.txt,undef],[2.txt,undef],[3.txt,undef],
#                           [a.txt,undef],[b.txt,undef],[c.txt,undef]]

#Note that this subroutine also detects input on standard input and treats it
#as an input of the same type as the first array in the file types array passed
#in.  If there is only one input file in that array, it will be considered to
#be a file name "stub" to be used to append outfile suffixes.

#Globals used: $output_mode
sub getFileSets
  {
    my $file_types_array = $_[0]; #A 3D array where the outer array specifies
                                  #file type (e.g. all files supplied by
                                  #instances of -i), the next array specifies
                                  #a specific instance of an option/flag (e.g.
                                  #the first instance of -i on the command
                                  #line) and the inner-most array contains the
                                  #arguments to that instance of that flag.
    my $outfile_suffixes = $_[1]; #OPTIONAL: An array (2D) no larger than
                                  #file_types_array's outer array (multiple
                                  #suffixes per input file type).  The order of
                                  #the suffix types must correspond to the
                                  #order of the input file types.  I.e. the
                                  #outer array of the file_types_array must
                                  #have the same corresponding order of type
                                  #elements (though it may contain fewer
                                  #elements if (e.g.) only 1 type of input file
                                  #has output files).  E.g. If the first type
                                  #in the file_types_array is files submitted
                                  #with -i, the first suffix will be appended
                                  #to files of type 1.  Note that if suffixes
                                  #are provided, any type without a suffix will
                                  #not be present in the returned outfile array
                                  #(there will be an undefined value as a
                                  #placeholder).  If no suffixes are provided,
                                  #the returned outfile array will contain
                                  #outfile stubs for every input file type to
                                  #which you must append your own suffix.
    my $outdir_array     = $_[2]; #OPTIONAL: A 2D array of output directories.
                                  #The dimensions of this array must either be
                                  #1x1, 1xN, or NxM where N or NxM must
                                  #correspond to the dimensions of one of the
                                  #input file types.  See notes above for an
                                  #example.  Every input file combination will
                                  #output to a single output directory.  Also
                                  #note that if suffixes are provided, any type
                                  #without a suffix will not be present in the
                                  #returned outfile array.  If no suffixes are
                                  #provided, the returned outfile array will
                                  #contain outfile stubs to which you must
                                  #append your own suffix.
    my $output_conf_mode = defined($_[3]) ? $_[3] :
      (defined($output_mode) ? $output_mode : 'error'); #OPTIONAL [error]
                                  #{aggregate,split,error} The Output conflicts
                                  #mode resolves what to try to do when
                                  #multiple input file combinations output to
                                  #the same output file.  This can be a 2D
                                  #array corresponding to the dimensions of the
                                  #outfile_suffixes array, filled with modes
                                  #for each outfile type (implied by the
                                  #suffixes) or it can be a 1D array (assuming
                                  #there's only one inner outfile suffixes
                                  #array, or it can be a single scalar value
                                  #that is applied to all outfile suffixes.)
    my $outfile_stub = defined($default_stub) ? $default_stub : 'STDIN';

    #eval {use Data::Dumper;1} if($DEBUG < 0);

    debug({LEVEL => -99},"Num initial arguments: [",scalar(@_),"].");

    debug({LEVEL => -99},"Initial size of file types array: [",
	  scalar(@$file_types_array),"].");

    ##
    ## Error check/fix the file_types_array (a 3D array of strings)
    ##
    if(ref($file_types_array) ne 'ARRAY')
      {
	#Allow them to submit scalars of everything
	if(ref(\$file_types_array) eq 'SCALAR')
	  {$file_types_array = [[[$file_types_array]]]}
	else
	  {
	    error("Expected an array for the first argument, but got a [",
		  ref($file_types_array),"].");
	    quit(-9);
	  }
      }
    elsif(scalar(grep {ref($_) ne 'ARRAY'} @$file_types_array))
      {
	my @errors = map {ref(\$_)} grep {ref($_) ne 'ARRAY'}
	  @$file_types_array;
	#Allow them to have submitted an array of scalars
	if(scalar(@errors) == scalar(@$file_types_array) &&
	   scalar(@errors) == scalar(grep {$_ eq 'SCALAR'} @errors))
	  {$file_types_array = [[$file_types_array]]}
	else
	  {
	    @errors = map {ref($_) eq '' ? ref(\$_) : ref($_)}
	      grep {ref($_) ne 'ARRAY'}
	      @$file_types_array;
	    error("Expected an array of arrays for the first argument, but ",
		  "found a [",join(',',@errors),"] inside the outer array.");
	    quit(-10);
	  }
      }
    elsif(scalar(grep {my @x=@$_;scalar(grep {ref($_) ne 'ARRAY'} @x)}
		 @$file_types_array))
      {
	#Look for SCALARs
	my @errors = map {my @x=@$_;map {ref(\$_)} @x}
	  grep {my @x=@$_;scalar(grep {ref($_) ne 'ARRAY'} @x)}
	    @$file_types_array;
	debug({LEVEL => -99},"ERRORS ARRAY: [",join(',',@errors),"].");
	#Allow them to have submitted an array of arrays of scalars
	if(scalar(@errors) == scalar(map {@$_} @$file_types_array) &&
	   scalar(@errors) == scalar(grep {$_ eq 'SCALAR'} @errors))
	  {$file_types_array = [$file_types_array]}
	else
	  {
	    #Reset the errors because I'm not looking for SCALARs anymore
	    @errors = map {my @x=@$_;'[' .
			     join('],[',
				  map {ref($_) eq '' ? 'SCALAR' : ref($_)} @x)
			       . ']'}
	      @$file_types_array;
	    error("Expected an array of arrays of arrays for the first ",
		  "argument, but got an array of arrays of [",
		  join(',',@errors),"].");
	    quit(-11);
	  }
      }
    elsif(scalar(grep {my @x = @$_;
		       scalar(grep {my @y = @$_;
				    scalar(grep {ref(\$_) ne 'SCALAR'}
					   @y)} @x)} @$file_types_array))
      {
	my @errors = map {my @x = @$_;map {my @y = @$_;map {ref($_)} @y} @x}
	  grep {my @x = @$_;
		scalar(grep {my @y = @$_;
			     scalar(grep {ref(\$_) ne 'SCALAR'} @y)} @x)}
	    @$file_types_array;
	error("Expected an array of arrays of arrays of scalars for the ",
	      "first argument, but got an array of arrays of [",
	      join(',',@errors),"].");
	quit(-12);
      }

    debug({LEVEL => -99},"Size of file types array after input check/fix: [",
	  scalar(@$file_types_array),"].");

    ##
    ## Error-check/fix the outfile_suffixes array (a 2D array of strings)
    ##
    my $suffix_provided = [map {0} @$file_types_array];
    if(defined($outfile_suffixes))
      {
	if(ref($outfile_suffixes) ne 'ARRAY')
	  {
	    #Allow them to submit scalars of everything
	    if(!defined($outfile_suffixes) ||
	       ref(\$outfile_suffixes) eq 'SCALAR')
	      {
		$suffix_provided->[0] = 1;
		$outfile_suffixes = [[$outfile_suffixes]];
	      }
	    else
	      {
		error("Expected an array for the second argument, but got a [",
		      ref($outfile_suffixes),"].");
		quit(-28);
	      }
	  }
	elsif(scalar(grep {!defined($_) || ref($_) ne 'ARRAY'}
		     @$outfile_suffixes))
	  {
	    my @errors = map {defined($_) ? ref(\$_) : $_}
	      grep {!defined($_) || ref($_) ne 'ARRAY'} @$outfile_suffixes;
	    #Allow them to have submitted an array of scalars
	    if(scalar(@errors) == scalar(@$outfile_suffixes) &&
	       scalar(@errors) == scalar(grep {!defined($_) || $_ eq 'SCALAR'}
					 @errors))
	      {$outfile_suffixes = [$outfile_suffixes]}
	    else
	      {
		@errors = map {ref($_)} grep {ref($_) ne 'ARRAY'}
		  @$outfile_suffixes;
		error("Expected an array of arrays for the second argument, ",
		      "but got an array of [",join(',',@errors),"].");
		quit(-29);
	      }
	  }
	elsif(scalar(grep {my @x=@$_;scalar(grep {ref(\$_) ne 'SCALAR'} @x)}
		     @$outfile_suffixes))
	  {
	    #Reset the errors because I'm not looking for SCALARs anymore
	    my @errors = map {my @x=@$_;map {ref($_)} @x}
	      grep {my @x=@$_;scalar(grep {ref($_) ne 'ARRAY'} @x)}
		@$outfile_suffixes;
	    error("Expected an array of arrays of scalars for the second ",
		  "argument, but got an array of arrays of [",
		  join(',',@errors),"].");
	    quit(-30);
	  }

	foreach my $suffix_index (0..$#{$outfile_suffixes})
	  {$suffix_provided->[$suffix_index] =
	     defined($outfile_suffixes->[$suffix_index]) &&
	       scalar(@{$outfile_suffixes->[$suffix_index]})}
      }

    ##
    ## Error-check/fix the outdir_array (a 2D array of strings)
    ##
    my $outdirs_provided = 0;
    if(defined($outdir_array) && scalar(@$outdir_array))
      {
	#Error check the outdir array to make sure it's a 2D array of strings
	if(ref($outdir_array) ne 'ARRAY')
	  {
	    #Allow them to submit scalars of everything
	    if(ref(\$outdir_array) eq 'SCALAR')
	      {
		$outdirs_provided = 1;
		$outdir_array     = [[$outdir_array]];
	      }
	    else
	      {
		error("Expected an array for the third argument, but got a [",
		      ref($outdir_array),"].");
		quit(-14);
	      }
	  }
	elsif(scalar(grep {ref($_) ne 'ARRAY'} @$outdir_array))
	  {
	    my @errors = map {ref(\$_)} grep {ref($_) ne 'ARRAY'}
	      @$outdir_array;
	    #Allow them to have submitted an array of scalars
	    if(scalar(@errors) == scalar(@$outdir_array) &&
	       scalar(@errors) == scalar(grep {$_ eq 'SCALAR'} @errors))
	      {
		$outdirs_provided = 1;
		$outdir_array = [$outdir_array];
	      }
	    else
	      {
		@errors = map {ref($_)} grep {ref($_) ne 'ARRAY'}
		  @$outdir_array;
		error("Expected an array of arrays for the third argument, ",
		      "but got an array of [",join(',',@errors),"].");
		quit(-15);
	      }
	  }
	elsif(scalar(grep {my @x=@$_;scalar(grep {ref(\$_) ne 'SCALAR'} @x)}
		     @$outdir_array))
	  {
	    #Look for SCALARs
	    my @errors = map {my @x=@$_;map {ref($_)} @x}
	      grep {my @x=@$_;scalar(grep {ref(\$_) ne 'SCALAR'} @x)}
		@$outdir_array;
	    error("Expected an array of arrays of scalars for the third ",
		  "argument, but got an array of arrays of [",
		  join(',',@errors),"].");
	    quit(-16);
	  }
	else
	  {$outdirs_provided = 1}

	#If any outdirs are empty strings, error out & quit
	my $empties_exist = scalar(grep {my @x=@$_;scalar(grep {$_ eq ''} @x)}
				   @$outdir_array);
	if($empties_exist)
	  {
	    error("Output directories may not be empty strings.");
	    quit(-27);
	  }
      }

    #debug({LEVEL => -99},"First output conf mode: ",
    #	  Dumper($output_mode));

    ##
    ## Error-check/fix the output_conf_mode (a 2D array of strings)
    ##
    if(ref($output_conf_mode) ne 'ARRAY')
      {
	#Allow them to submit scalars of everything
	if(ref(\$output_conf_mode) eq 'SCALAR')
	  {
	    #Copy this value to all places corresponding to outfile_suffixes
	    my $tmp_out_mode  = $output_conf_mode;
	    $output_conf_mode = [];
	    foreach my $sub_array (@$outfile_suffixes)
	      {
		push(@$output_conf_mode,[]);
		foreach my $suff (@$sub_array)
		  {push(@{$output_conf_mode->[-1]},
			(defined($suff) ? $tmp_out_mode : undef))}
	      }
	  }
	else
	  {
	    error("Expected an array or scalar for the fourth argument, but ",
		  "got a [",ref($output_conf_mode),"].");
	    quit(-28);
	  }
      }
    elsif(scalar(grep {!defined($_) || ref($_) ne 'ARRAY'} @$output_conf_mode))
      {
	my @errors = map {defined($_) ? ref(\$_) : $_}
	  grep {!defined($_) || ref($_) ne 'ARRAY'} @$output_conf_mode;
	#Allow them to have submitted an array of scalars
	if(scalar(@errors) == scalar(@$output_conf_mode) &&
	   scalar(@errors) == scalar(grep {!defined($_) || $_ eq 'SCALAR'}
				     @errors))
	  {$output_conf_mode = [$output_conf_mode]}
	else
	  {
	    @errors = map {ref($_)} grep {ref($_) ne 'ARRAY'}
	      @$output_conf_mode;
	    error("Expected an array of arrays for the fourth argument, ",
		  "but got an array of [",join(',',@errors),"].");
	    quit(-29);
	  }
      }
    elsif(scalar(grep {my @x=@$_;scalar(grep {ref(\$_) ne 'SCALAR'} @x)}
		 @$output_conf_mode))
      {
	#Reset the errors because I'm not looking for SCALARs anymore
	my @errors = map {my @x=@$_;map {ref($_)} @x}
	  grep {my @x=@$_;scalar(grep {ref($_) ne 'ARRAY'} @x)}
	    @$output_conf_mode;
	error("Expected an array of arrays of scalars for the fourth ",
	      "argument, but got an array of arrays of [",
	      join(',',@errors),"].");
	quit(-30);
      }

    #Error-check the values of the output_conf_mode 2D array
    my $conf_errs = [];
    foreach my $conf_array (@$output_conf_mode)
      {
	foreach my $conf_mode (@$conf_array)
	  {
	    if(!defined($conf_mode))
	      {$conf_mode = (defined($output_mode) ? $output_mode : 'error')}
	    elsif($conf_mode =~ /^e/i)
	      {$conf_mode = 'error'}
	    elsif($conf_mode =~ /^a/i)
	      {$conf_mode = 'aggregate'}
	    elsif($conf_mode =~ /^s/i)
	      {$conf_mode = 'split'}
	    else
	      {push(@$conf_errs,$conf_mode)}
	  }
      }
    if(scalar(@$conf_errs))
      {
	error("Invalid output modes detected: [",join(',',@$conf_errs),
	      "].  Valid values are: [aggregate,error,split].");
	quit(-31);
      }

    debug({LEVEL => -99},
	  "Contents of file types array before adding dash file: [(",
	  join(')(',map {my $t=$_;'{' .
			   join('}{',map {my $e=$_;'[' . join('][',@$e) . ']'}
				@$t) . '}'} @$file_types_array),")].");

    #debug({LEVEL => -99},"Output conf mode after manipulation: ",
    #	  Dumper($output_conf_mode));

    ##
    ## If standard input is present, ensure it's in the file_types_array
    ##
    if(!isStandardInputFromTerminal())
      {
	#The first element of the file types array is specifically the type of
	#input file that can be provided via STDIN.  However, a user may
	#explicitly supply a dash on the command line to have the STDIN go to a
	#different parameter instead of the default
	debug({LEVEL => -99},"file_types_array->[0] is [",
	      (defined($file_types_array->[0]) ? 'defined' : 'undefined'),
	      "].");

	if(!defined($file_types_array->[0]))
	  {$file_types_array->[0] = []}

	my $input_files = $file_types_array->[0];
	my $num_input_files = scalar(grep {$_ ne '-'} map {@$_} @$input_files);
	my $dash_was_explicit =
	  scalar(grep {my $t=$_;scalar(grep {my $e=$_;
					     scalar(grep {$_ eq '-'} @$e)}
				       @$t)} @$file_types_array);
	my $type_index_of_dash = 0;
	if($dash_was_explicit)
	  {$type_index_of_dash =
	     (scalar(grep {my $t=$_;scalar(grep {my $e=$_;
						 scalar(grep {$_ eq '-'} @$e)}
					   @{$file_types_array->[$t]})}
		     (0..$#{$file_types_array})))[0]}

	debug({LEVEL => -99},"There are $num_input_files input files.");
	debug({LEVEL => -99},"Outfile stub: $outfile_stub.");

	#If there's only one input file detected, the dash for STDIN was not
	#explicitly provided, and an outfile suffix has been provided, use that
	#input file as a stub for the output file name construction
	if($num_input_files == 1 && !$dash_was_explicit &&
	   defined($outfile_suffixes) && scalar(@$outfile_suffixes) &&
	   defined($outfile_suffixes->[0]))
	  {
	    $outfile_stub = (grep {$_ ne '-'} map {@$_} @$input_files)[0];

	    #Unless the dash was explicitly supplied as a separate file, treat
	    #the input file as a stub only (not as an actual input file
	    @$input_files = ();
	    $num_input_files = 0;

	    #If the stub contains a directory path AND outdirs were supplied
	    if($outfile_stub =~ m%/% &&
	       defined($outdir_array) &&
	       #Assume the outdir is good if
	       ((ref($outdir_array) eq 'ARRAY' && scalar(@$outdir_array)) ||
		ref(\$outdir_array) eq 'SCALAR'))
	      {
		error("You cannot use --outdir and embed a directory path in ",
		      "the outfile stub (-i with a single argument when ",
		      "redirecting standard input in).  Please use one or ",
		      "the other.");
		quit(-13);
	      }
	  }
	#If standard input has been redirected in (which is true because we're
	#here) and an outfule_suffix has been defined for the type of files
	#that the dash is in or will be in, inform the user about the name of
	#the outfile using the default stub for STDIN
	elsif(defined($outfile_suffixes) &&
	      scalar(@$outfile_suffixes) > $type_index_of_dash &&
	      defined($outfile_suffixes->[$type_index_of_dash]))
	  {verbose("Input on STDIN will be referred to as [$outfile_stub].")}

	debug({LEVEL => -99},"Outfile stub: $outfile_stub.");

	#Unless the dash was supplied explicitly by the user, push it on
	unless($dash_was_explicit)
	  {
	    debug({LEVEL => -99},"Pushing on the dash file to the other ",
		  "$num_input_files files.");
	    debug({LEVEL => -99},
		  "input_files is ",(defined($input_files) ? '' : 'un'),
		  "defined, is of type [",ref($input_files),
		  "], and contains [",
		  (defined($input_files) ?
		   scalar(@$input_files) : 'undefined'),"] items.");

	    debug({LEVEL => -99},
		  ($input_files eq $file_types_array->[0] ?
		   'input_files still references the first element in the ' .
		   'file types array' : 'input_files has gotten overwritten'));

	    #Create a new 1st input file set with it as the only file member
	    unshift(@$input_files,['-']);

	    debug({LEVEL => -99},
		  ($input_files eq $file_types_array->[0] ?
		   'input_files still references the first element in the ' .
		   'file types array' : 'input_files has gotten overwritten'));
	  }
      }

    debug({LEVEL => -99},
	  "Contents of file types array after adding dash file: [(",
	  join(')(',map {my $t=$_;'{' .
			   join('}{',map {my $e=$_;'[' . join('][',@$e) . ']'}
				@$t) . '}'} @$file_types_array),")].");

    ##
    ## Error-check/fix the file_types_array with the outfile_suffixes array
    ##
    if(scalar(@$file_types_array) < scalar(@$outfile_suffixes))
      {
	error("More outfile suffixes (",scalar(@$outfile_suffixes),"): [",
	      join(',',map {defined($_) ? $_ : 'undef'} @$outfile_suffixes),
	      "] than file types [",scalar(@$file_types_array),"].");
	quit(-30);
      }
    #Elsif the sizes are different, top off the outfile suffixes with undefs
    elsif(scalar(@$file_types_array) > scalar(@$outfile_suffixes))
      {while(scalar(@$file_types_array) > scalar(@$outfile_suffixes))
	 {push(@$outfile_suffixes,undef)}}

    ##
    ## Error-check/fix output_conf_mode array with the outfile_suffixes array
    ##
    #Make sure that the output_conf_mode 2D array has the same dimensions as
    #the outfile_suffixes array - assuming any missing values that are defined
    #in the suffixes array default to 'error'.
    #If a subarray is missing and the original first subarray was size 1,
    #default to its value, otherwise default to undef.  E.g. a suffix array
    #such as [[a,b,c][d,e][undef]] and output_conf_mode of [[error]] will
    #generate a new output_conf_mode array of:
    #[[error,error,error][error,error][undef]].
    if(scalar(@$output_conf_mode) > scalar(@$outfile_suffixes))
      {
	error("Output mode array is out of bounds.  Must have as ",
	      "many or fewer members as the outfile suffixes array.");
	quit(-31);
      }
    my $global_conf_mode = (scalar(@$output_conf_mode) == 1 &&
			    scalar(@{$output_conf_mode->[0]}) == 1) ?
			      $output_conf_mode->[0] :
				(defined($output_mode) ?
				 $output_mode : 'error');
    #Create sub-arrays as needed, but don't make them inadvertently bigger
    while(scalar(@$output_conf_mode) < scalar(@$outfile_suffixes))
      {
	#Determine what the next index will be
	my $suff_array_index = scalar(@$output_conf_mode);
	push(@$output_conf_mode,
	     (defined($outfile_suffixes->[$suff_array_index]) ?
	      (scalar(@{$outfile_suffixes->[$suff_array_index]}) ?
	       [$global_conf_mode] : []) : undef));
      }
    foreach my $suff_array_index (0..$#{$outfile_suffixes})
      {
	next unless(defined($outfile_suffixes->[$suff_array_index]));
	#Make sure it's not bigger than the suffixes subarray
	if(scalar(@{$output_conf_mode->[$suff_array_index]}) >
	   scalar(@{$outfile_suffixes->[$suff_array_index]}))
	  {
	    error("Output mode sub-array at index [$suff_array_index] is out ",
		  "of bounds.  Must have as many or fewer members as the ",
		  "outfile suffixes array.");
	    quit(-32);
	  }
	while(scalar(@{$output_conf_mode->[$suff_array_index]}) <
	      scalar(@{$outfile_suffixes->[$suff_array_index]}))
	  {
	    push(@{$output_conf_mode->[$suff_array_index]},
		 (scalar(@{$output_conf_mode->[$suff_array_index]}) ?
		  $output_conf_mode->[0] : $global_conf_mode));
	  }
      }

    ##
    ## Special case (probably unnecessary now with upgrades in 6/2014)
    ##
    my $one_type_mode = 0;
    #If there's only 1 input file type and (no outdirs or 1 outdir), merge all
    #the sub-arrays
    if(scalar(@$file_types_array) == 1 &&
       (!$outdirs_provided || (scalar(@$outdir_array) == 1 &&
			       scalar(@{$outdir_array->[0]}) == 1)))
      {
	$one_type_mode = 1;
	debug({LEVEL => -99},"Only 1 type of file was submitted, so the ",
	      "array is being preemptively flattened.");

	my @merged_array = ();
	foreach my $row_array (@{$file_types_array->[0]})
	  {push(@merged_array,@$row_array)}
	$file_types_array->[0] = [[@merged_array]];
      }

    debug({LEVEL => -99},
	  "Contents of file types array after merging sub-arrays: [(",
	  join(')(',map {my $t=$_;'{' .
			   join('}{',map {my $e=$_;'[' . join('][',@$e) . ']'}
				@$t) . '}'} @$file_types_array),")].");

    debug({LEVEL => -99},
	  "OUTDIR ARRAY DEFINED?: [",defined($outdir_array),"] SIZE: [",
	  (defined($outdir_array) ? scalar(@$outdir_array) : '0'),"].");

    ##
    ## Prepare to treat outdirs the same as infiles
    ##
    #If output directories were supplied, push them onto the file_types_array
    #so that they will be error-checked and modified in the same way below.
    if($outdirs_provided)
      {push(@$file_types_array,$outdir_array)}

    debug({LEVEL => -99},
	  "Contents of file types array after adding outdirs: [(",
	  join(')(',map {my $t=$_;'{' .
			   join('}{',map {my $e=$_;'[' . join('][',@$e) . ']'}
				@$t) . '}'} @$file_types_array),")].");

    ##
    ## Prepare to error-check file/dir array dimensions
    ##
    my $twods_exist = scalar(grep {my @x = @$_;
			      scalar(@x) > 1 &&
				scalar(grep {scalar(@$_) > 1} @x)}
			     @$file_types_array);
    debug({LEVEL => -99},"2D? = $twods_exist");

    #Determine the maximum dimensions of any 2D file arrays
    my $max_num_rows = (#Sort on descending size so we can grab the largest one
			sort {$b <=> $a}
			#Convert the sub-arrays to their sizes
			map {scalar(@$_)}
			#Grep for arrays larger than 1 with subarrays larger
			#than 1
			grep {my @x = @$_;
			      !$twods_exist ||
				(scalar(@x) > 1 &&
				 scalar(grep {scalar(@$_) > 1} @x))}
			@$file_types_array)[0];

    my $max_num_cols = (#Sort on descending size so we can grab the largest one
			sort {$b <=> $a}
			#Convert the sub-arrays to their sizes
			map {my @x = @$_;(sort {$b <=> $a}
					  map {scalar(@$_)} @x)[0]}
			#Grep for arrays larger than 1 with subarrays larger
			#than 1
			grep {my @x = @$_;
			      !$twods_exist ||
				(scalar(@x) > 1 &&
				 scalar(grep {scalar(@$_) > 1} @x))}
			@$file_types_array)[0];

    debug({LEVEL => -99},
	  "Max number of rows and columns in 2D arrays: [$max_num_rows,",
	  "$max_num_cols].");

    debug({LEVEL => -99},"Size of file types array: [",
	  scalar(@$file_types_array),"].");

    debug({LEVEL => -99},
	  "Contents of file types array before check/transpose: [(",
	  join(')(',map {my $t=$_;'{' .
			   join('}{',map {my $e=$_;'[' . join('][',@$e) . ']'}
				@$t) . '}'} @$file_types_array),")].");

    ##
    ## Error-check/transpose file/dir array dimensions
    ##
    #Error check to make sure that all file type arrays are either the two
    #dimensions determined above or a 1D array equal in size to either of the
    #dimensions
    my $row_inconsistencies = 0;
    my $col_inconsistencies = 0;
    my $twod_col_inconsistencies = 0;
    my @dimensionalities    = (); #Keep track for checking outfile stubs later
    foreach my $file_type_array (@$file_types_array)
      {
	my @subarrays = @$file_type_array;

	#If it's a 2D array (as opposed to just 1 col or row), look for
	#inconsistencies in the dimensions of the array
	if(scalar(scalar(@subarrays) > 1 &&
		  scalar(grep {scalar(@$_) > 1} @subarrays)))
	  {
	    push(@dimensionalities,2);

	    #If the dimensions are not the same as the max
	    if(scalar(@subarrays) != $max_num_rows)
	      {
		debug({LEVEL => -99},"Row inconsistencies in 2D arrays found");
		$row_inconsistencies++;
	      }
	    elsif(scalar(grep {scalar(@$_) != $max_num_cols} @subarrays))
	      {
		debug({LEVEL => -99},"Col inconsistencies in 2D arrays found");
		$col_inconsistencies++;
		$twod_col_inconsistencies++;
	      }
	  }
	else #It's a 1D array (i.e. just 1 col or row)
	  {
	    push(@dimensionalities,1);

	    #If there's only 1 row
	    if(scalar(@subarrays) == 1)
	      {
		debug({LEVEL => -99},"There's only 1 row of size ",
		      scalar(@{$subarrays[0]}),". Max cols: [$max_num_cols]. ",
		      "Max rows: [$max_num_rows]");
		if(#$twods_exist &&
		   !$one_type_mode &&
		   scalar(@{$subarrays[0]}) != $max_num_rows &&
		   scalar(@{$subarrays[0]}) != $max_num_cols &&
		   scalar(@{$subarrays[0]}) > 1)
		  {
		    debug({LEVEL => -99},
			  "Col inconsistencies in 1D arrays found (size: ",
			  scalar(@{$subarrays[0]}),")");
		    $col_inconsistencies++;
		  }
		#If the 1D array needs to be transposed because it's a 1 row
		#array and its size matches the number of rows, transpose it
		elsif(#$twods_exist &&
		      !$one_type_mode &&
		      $max_num_rows != $max_num_cols &&
		      scalar(@{$subarrays[0]}) == $max_num_rows)
		  {@$file_type_array = transpose(\@subarrays)}
	      }
	    #Else if there's only 1 col
	    elsif(scalar(@subarrays) == scalar(grep {scalar(@$_) == 1}
					       @subarrays))
	      {
		debug({LEVEL => -99},
		      "There's only 1 col of size ",scalar(@subarrays),
		      "\nThe max number of columns is $max_num_cols");
		if(#$twods_exist &&
		   !$one_type_mode &&
		   scalar(@subarrays) != $max_num_rows &&
		   scalar(@subarrays) != $max_num_cols &&
		   scalar(@subarrays) > 1)
		  {
		    debug({LEVEL => -99},"Row inconsistencies in 1D arrays ",
			  "found (size: ",scalar(@subarrays),")");
		    $row_inconsistencies++;
		  }
		#If the 1D array needs to be transposed because it's a 1 col
		#array and its size matches the number of cols, transpose it
		elsif(#$twods_exist &&
		      !$one_type_mode &&
		      $max_num_rows != $max_num_cols &&
		      scalar(@subarrays) == $max_num_cols)
		  {@$file_type_array = transpose(\@subarrays)}
	      }
	    else #There must be 0 cols
	      {
		debug({LEVEL => -99},"Col inconsistencies in 0D arrays found");
		$col_inconsistencies++;
	      }

	    debug({LEVEL => -99},"This should be array references: [",
		  join(',',@$file_type_array),"].");
	  }
      }

    debug({LEVEL => -99},
	  "Contents of file types array after check/transpose: [(",
	  join(')(',map {my $t=$_;'{' .
			   join('}{',map {my $e=$_;'[' . join('][',@$e) . ']'}
				@$t) . '}'} @$file_types_array),")].");

    #Note that if the user has supplied multiple input files that create an
    #output file of the same name, there are a few possible outcomes.  If the
    #output mode is aggregate, it is assumed that the user intends the output
    #to be concatenated in a single file.  If in split mode, the script
    #compounds the the input file names and re-check for uniqueness.  If in
    #error mode, the script will quit with an error about conflicting outfile
    #names.

    ##
    ## Create sets/combos (handling the default stub and prepending outdirs)
    ##
    my($infile_sets_array,$outfiles_sets_array,$stub_sets_array);
    if(defined($outdir_array) && scalar(@$outdir_array))
      {
	debug({LEVEL => -99},"outdir array has [",scalar(@$outdir_array),
	      "] members.");

	my $unique_out_check      = {};
	my $nonunique_found       = 0;
	my $tmp_infile_sets_array = getMatchedSets($file_types_array);

	foreach my $infile_set (@$tmp_infile_sets_array)
	  {
	    debug({LEVEL => -99},"Infile set with dirname: [",
		  join(',',map {defined($_) ? $_ : 'undef'} @$infile_set),
		  "].");

	    my $stub_set = [];
	    my $dirname = $infile_set->[-1];
	    #For every file (except the last one (which is an output directory)
	    foreach my $file (@{$infile_set}[0..($#{$infile_set} - 1)])
	      {
		my $stub = $file;
		if(defined($stub))
		  {
		    #Us the default outfile stub if this is a redirect
		    $stub = $outfile_stub if($stub eq '-');

		    #Eliminate any path strings from the file name
		    $stub =~ s/.*\///;

		    #Prepend the outdir path
		    my $new_outfile_stub = $dirname .
		      ($dirname =~ /\/$/ ? '' : '/') . $stub;

		    debug({LEVEL => -99},
			  "Prepending directory $new_outfile_stub using [",
			  "$file].");

		    push(@$stub_set,$new_outfile_stub);

		    $unique_out_check->{$new_outfile_stub}->{$file}++;

		    #Check for conflicting output file names from multiple
		    #different input files that will overwrite one another
		    #(the same output file from the same input file is OK -
		    #we'll assume they won't open it more than once
		    if(scalar(keys(%{$unique_out_check->{$new_outfile_stub}}))
		       > 1)
		      {$nonunique_found = 1}
		  }
		else
		  {push(@$stub_set,$stub)}
	      }
	    push(@$infile_sets_array,
		 [@{$infile_set}[0..($#{$infile_set} - 1)]]);
	    push(@$stub_sets_array,$stub_set);
	  }

	if($nonunique_found)
	  {
	    error('The following output file name stubs were created by ',
		  'multiple input file names.  Their output files will be ',
		  'overwritten when used.  Please make sure each like-named ',
		  'input file (from a different source directory) outputs to ',
		  'a different output directory or that the input file names ',
		  'are not the same.  Offending file stub conflicts: [',
		  join(',',map {"stub $_ is generated by [" .
				  join(',',
				       keys(%{$unique_out_check->{$_}})) .
					 "]"}
		       (grep {scalar(keys(%{$unique_out_check->{$_}})) > 1}
			keys(%$unique_out_check))),'].');
	    quit(-1);
	  }
      }
    else
      {
	$infile_sets_array = getMatchedSets($file_types_array);
	$stub_sets_array   = copyArray($infile_sets_array);

	#Replace any dashes with the outfile stub
	foreach my $stub_set (@$stub_sets_array)
	  {foreach my $stub (@$stub_set)
	     {$stub = $outfile_stub if(defined($stub) && $stub eq '-')}}
      }

    #debug({LEVEL => -1},"Stubs before making them unique: ",
    #	  Dumper($stub_sets_array));

    #makeCheckOutputs returns an outfiles_sets_array and stub_sets_array that
    #have been confirmed to not overwrite each other or existing files.  It
    #quits the script if it finds a conflict.  It uses the output conf mode
    #variable to know when to compound file names to avoid potential
    #overwrites, but either compounds or quits with an error based on the mode
    #(aggregate, split, or error).
    ($outfiles_sets_array,
     $stub_sets_array) = makeCheckOutputs($stub_sets_array,
					  $outfile_suffixes,
					  $output_conf_mode);

    #debug({LEVEL => -1},"Stubs after making them unique: ",
    #	  Dumper($stub_sets_array));
    #debug({LEVEL => -1},"Outfiles from the stubs: ",
    #	  Dumper($outfiles_sets_array));

    debug({LEVEL => -1},"Processing input file sets: [(",
	  join('),(',(map {my $a = $_;join(',',map {defined($_) ? $_ : 'undef'}
					   @$a)} @$infile_sets_array)),
	  ")] and output stubs: [(",
	  join('),(',
               (map {my $a = $_;
                     join(',',map {my $b = $_;defined($b) ? '[' .
                                     join('],[',map {defined($_) ?
                                                       ($_ eq '' ?
                                                        'EMPTY-STRING' : $_) :
                                                         'undef'} @$b) .
                                              ']' : 'undef'}
		@$a)} @$outfiles_sets_array)),")].");

    return($infile_sets_array,$outfiles_sets_array,$stub_sets_array);
  }

#This subroutine transposes a 2D array (i.e. it swaps rows with columns).
#Assumes argument is a 2D array.  If the number of columns is not the same from
#row to row, it fills in missing elements with an empty string.
sub transpose
  {
    my $twod_array    = $_[0];
    debug({LEVEL => -99},"Transposing: [(",
	  join('),(',map {join(',',@$_)} @$twod_array),")].");
    my $transposition = [];
    my $last_row = scalar(@$twod_array) - 1;
    my $last_col = (sort {$b <=> $a} map {scalar(@$_)} @$twod_array)[0] - 1;
    debug({LEVEL => -99},"Last row: $last_row, Last col: $last_col.");
    foreach my $col (0..$last_col)
      {push(@$transposition,
	    [map {$#{$twod_array->[$_]} >= $col ?
		    $twod_array->[$_]->[$col] : ''}
	     (0..$last_row)])}
    debug({LEVEL => -99},"Transposed: [(",
	  join('),(',map {join(',',@$_)} @$transposition),")].");
    return(wantarray ? @$transposition : $transposition);
  }

#This subroutine takes an array of file names and an outfile suffix and returns
#any file names that already exist in the file system
sub getExistingOutfiles
  {
    my $outfile_stubs_for_input_files = $_[0];
    my $outfile_suffix                = scalar(@_) >= 2 ? $_[1] : ''; #OPTIONAL
                                        #undef means there won't be outfiles
                                        #Empty string means that the files in
                                        #$_[0] are already outfile names
    my $existing_outfiles             = [];

    #Check to make sure previously generated output files won't be over-written
    #Note, this does not account for output redirected on the command line.
    #Also, outfile stubs are checked for future overwrite conflicts in
    #getFileSets (i.e. separate files slated for output with the same name)

    #For each output file *stub*, see if the expected outfile exists
    foreach my $outfile_stub (grep {defined($_)}
			      @$outfile_stubs_for_input_files)
      {if(-e "$outfile_stub$outfile_suffix")
	 {push(@$existing_outfiles,"$outfile_stub$outfile_suffix")}}

    return(wantarray ? @$existing_outfiles : $existing_outfiles);
  }

#This subroutine takes a 1D or 2D array of output directories and creates them
#(Only works on the last directory in a path.)  Returns non-zero if successful
#Globals used: $overwrite, $dry_run, $use_as_default
sub mkdirs
  {
    my @dirs            = @_;
    my $status          = 1;
    my @unwritable      = ();
    my @errored         = ();
    my $local_overwrite = defined($overwrite) ? $overwrite : 0;
    my $local_dry_run   = defined($dry_run)   ? $dry_run   : 0;
    my $seen            = {};

    #If --save-as-default was supplied, do not create any directories, because
    #the script is only going to save the command line options & quit
    return($status) if(defined($use_as_default) && $use_as_default);

    #Create the output directories
    if(scalar(@dirs))
      {
	foreach my $dir_set (@dirs)
	  {
	    my @dirlist = (ref($dir_set) eq 'ARRAY' ? @$dir_set : $dir_set);

	    foreach my $dir (@dirlist)
	      {
		next if(exists($seen->{$dir}));

		#If the directory exists and we're not going to overwrite it,
		#check it to see if we'll have a problem writing files to it
		#Note: overwrite has to be 2 or more to delete a directory
		if(-e $dir && $local_overwrite < 2)
		  {
		    #If the directory is not writable
		    if(!(-w $dir))
		      {push(@unwritable,$dir)}
		    #Else if we are in overwrite mode
		    elsif($local_overwrite)
		      {warning('The --overwrite flag will not empty or ',
			       'delete existing output directories.  If ',
			       'you wish to delete existing output ',
			       'directories, you must do it manually.')}
		  }
		#Else if this isn't a dry run
		elsif(!$local_dry_run)
		  {
		    if($overwrite > 1 && -e $dir)
		      {
			#We're only going to delete files if they have headers
			#indicating that they were created by a previous run of
			#this script

			deletePrevRunDir($dir);
		      }

		    #We're didn't delete manually created files above, so the
		    #directory may still exist and not need recreated
		    if(!(-e $dir))
		      {
			my $tmp_status = mkdir($dir);
			if(!$tmp_status)
			  {
			    $status = 0;
			    push(@errored,"$dir $!");
			  }
		      }
		  }
		#Else, check to see if creation is feasible in dry-run mode
		else
		  {
		    my $encompassing_dir = $dir;
		    $encompassing_dir =~ s%/$%%;
		    $encompassing_dir =~ s/[^\/]+$//;
		    $encompassing_dir = '.'
		      unless($encompassing_dir =~ /./);

		    if(!(-w $encompassing_dir))
		      {error("Unable to create directory: [$dir].  ",
			     "Encompassing directory is not writable.")}
		    else
		      {verbose("[$dir] Directory created.")}
		  }

		$seen->{$dir} = 1;
	      }
	  }

	if(scalar(@unwritable))
	  {
	    error("These output directories do not have write permission: [",
		  join(',',@unwritable),
		  "].  Please change the permissions to proceed.");
	    quit(-18) if(scalar(@errored) == 0);
	  }

	if(scalar(@errored))
	  {
	    error("These output directories could not be created: [",
		  join(',',@errored),
		  "].");
	    quit(-18);
	  }
      }

    return($status);
  }

#This subroutine will crawl through a directory and unlink any files that have
#headers indicating they were created by this script, and the directory itself
#if nothing is left
#Globals used: $overwrite
sub deletePrevRunDir
  {
    my $dir    = $_[0];
    my $status = 1;      #SUCCESS = 1, FAILURE = 0

    if($overwrite < 2)
      {
	$status = 0;
	warning("Removing an existing output directory such as [$dir] ",
		"requires --overwrite to be supplied more then once.");
	return($status);
      }

    my($dh);
    unless(opendir($dh, $dir))
      {
	error("Unable to open directory: [$dir]");
	$status = 0;
	return($status);
      }

    my $total = 0;
    my $deleted = 0;
    while(my $f = readdir($dh))
      {
	$total++;

	if(-d $f)
	  {$deleted += deletePrevRunDir("$dir/$f")}
	else
	  {
	    my $imadethis = iMadeThisBefore("$dir/$f");
	    if($imadethis && !unlink("$dir/$f"))
	      {
		error("Unable to delete file [$dir/$f] from previous run.  ",
		      $!);
		$status = 0;
	      }
	    elsif($imadethis)
	      {$deleted++}
	  }
      }

    closedir($dh);

    #If everything in the directory was successfully deleted, but we could not
    #delete this directory
    if($total == $deleted && !rmdir($dir))
      {$status = 0}

    return($status)
  }

sub iMadeThisBefore
  {
    my $file            = $_[0];
    my $imadethisbefore = 0;

    #Determine if the file was created while or after this script started
    my $lmdsecs = (stat($file))[9];
    if($lmdsecs >= $^T)
      {
	$imadethisbefore = 0;
	return($imadethisbefore);
      }

    #Guess whether the header in this file indicates that this script created
    #the file.  (Depends on whether the run included the header)
    unless(openIn(*DEL,$file,1))
      {
	error("Unable to determine if file [$file] was from a previous run.");
	return($imadethisbefore);
      }



    #TODO: Allow any file is a system temp directory do be deleted without
    #requiring a header



    my $script     = $0;
    $script        =~ s/^.*\/([^\/]+)$/$1/;
    my $script_pat = quotemeta($script);

    while(getLine(*DEL))
      {
	last unless(/^\s*#/);

	if(/$script_pat/)
	  {
	    $imadethisbefore = 1;
	    last;
	  }
      }

    closeIn(*DEL);

    return($imadethisbefore);
  }

#This subroutine checks for existing output files
#Globals used: $overwrite, $skip_existing
sub checkFile
  {
    my $output_file         = defined($_[0]) ? $_[0] : return(1);
    my $input_file_set      = $_[1]; #Optional: Used for verbose/error messages
    my $local_quiet         = scalar(@_) > 2 && defined($_[2]) ? $_[2] : 0;
    my $quit                = scalar(@_) > 3 && defined($_[3]) ? $_[3] : 1;
    my $status              = 1;
    my $local_overwrite     = defined($overwrite) ? $overwrite : 0;
    my $local_skip_existing = defined($skip_existing) ? $skip_existing : 0;

    if(-e $output_file)
      {
	debug({LEVEL => 2},"Output file: [$output_file] exists.");

	if($local_skip_existing)
	  {
	    verbose("[$output_file] Output file exists.  Skipping",
		    (defined($input_file_set) ?
                     (" input file(s): [",join(',',@$input_file_set),"]") :
                     ''),".") unless($local_quiet);
	    $status = 0;
	  }
	elsif(!$local_overwrite)
	  {
	    error("[$output_file] Output file exists.  Unable to ",
		  "proceed.  ",
                  (defined($input_file_set) ?
                   ("Encountered while processing input file(s): [",
		    join(',',grep {defined($_)} @$input_file_set),
		    "].  ") : ''),
                  "This may have been caused by multiple input files ",
		  "writing to one output file because there were not ",
		  "existing output files when this script started.  If any ",
		  "input files are writing to the same output file, you ",
		  "should have seen a warning about this above.  Otherwise, ",
		  "you may have multiple versions of this script running ",
		  "simultaneously.  Please check your input files and ",
		  "outfile suffixes to fix any conflicts or supply the ",
		  "--skip-existing or --overwrite.")
	      unless($local_quiet);
	    quit(-1) if($quit);
	    $status = 0;
	  }
      }
    else
      {debug({LEVEL => 2},"Output file: [$output_file] does not exist yet.")}

    return($status);
  }

#Uses globals: $dry_run
sub openOut
  {
    my $file_handle   = $_[0];
    my $output_file   = $_[1];
    my $local_select  = (scalar(@_) >= 3 ? $_[2] : undef);
    my $local_quiet   = (scalar(@_) >= 4 && defined($_[3]) ? $_[3] : 0);
    my $local_header  = (scalar(@_) >= 5 && defined($_[4]) ? $_[4] : 1);
    my $local_dry_run = defined($dry_run) ? $dry_run : 0;
    my $status        = 1;
    my($select);

    #Silently remove a single leading '>' character
    if($output_file =~ /^>[^>]/)
      {$output_file =~ s/^>//}
    elsif($output_file =~ /^\s*(\||\+|<|>)/)
      {
	my $errfound = $1;
	error("openOut only supports write mode and expects an output file ",
	      "name as the second argument.  Leading characters to control ",
	      "the output mode, such as [$errfound] in [$output_file] are ",
	      "not supported.");
	$status = 0;
	return($status);
      }
    elsif($output_file =~ /\|\s*$/)
      {
	my $errfound = $1;
	error("openOut only supports write mode and expects an output file ",
	      "name as the second argument.  Trailing characters to control ",
	      "the output, such as [$errfound] in [$output_file] are not ",
	      "supported.");
	$status = 0;
	return($status);
      }

    #Determine if we should select the output handle: default to user-specified
    #If not, select the handle if current default is STDOUT, else don't select
    if(defined($local_select))
      {
	#Set an explicit select
	$select = 2;
      }
    #Else if STDOUT is currently selected or the output file is not defined
    #(implying an anonymous file handle is being opened & selected)
    elsif(select() eq *STDOUT || !defined($output_file))
      {
	#Set an implicit select
	$select = 1;
      }
    #Else another handle is currently selected and select is supposed to be
    #implicit, so throw a warning and don't select
    else
      {
	my $selected_handle = select();
	my($selected_file);
	if(exists($main::open_handles->{$selected_handle}))
	  {
	    $selected_file = $main::open_handles->{$selected_handle}->{FILE};
	    warning("Only 1 output handle can be selected at a time.  Not ",
		    "selecting handle for output file [$output_file] because ",
		    "an open selected handle exists for file ",
		    "[$selected_file].");
	  }
	else
	  {warning("Only 1 output handle can be selected at a time.  Not ",
		    "selecting handle for output file [$output_file] because ",
		    "an untracked file handle has been selected.")}
	$select = 0;
      }

    debug({LEVEL => 2},"Output file is ",(defined($output_file) ? '' : 'NOT '),
          "defined",
	  (defined($output_file) ? " and is of type [" .
	   (ref($output_file) eq '' ? 'SCALAR' : ref($output_file)) . "]" :
	   ''),'.');

    #If there was no output file (or they explicitly sent in the STDOUT file
    #handle) assume user is outputting to STDOUT
    if(!defined($output_file) || $file_handle eq *STDOUT)
      {
        select(STDOUT) if($select);

        #If this is the first time encountering the STDOUT open
        if(!defined($main::open_handles) ||
           !exists($main::open_handles->{*STDOUT}))
          {
            verbose('[STDOUT] Opened for all output.') unless($local_quiet);

            #Store info. about the run as a comment at the top of the output
            #file if STDOUT has been redirected to a file
            if(!isStandardOutputToTerminal() && $local_header)
              {print(getHeader())}
          }

	$file_handle = *STDOUT;
	$main::open_handles->{*STDOUT}->{FILE}   = 'STDOUT';
	$main::open_handles->{*STDOUT}->{QUIET}  = $local_quiet;
	$main::open_handles->{*STDOUT}->{SELECT} = $select;
      }
    #else if the output file fails the overwrite protection check
    elsif(!checkFile($output_file,undef,$local_quiet,0))
      {$status = 0}
    #Else if this isn't a dry run and opening the output file fails
    elsif(!$local_dry_run && !open($file_handle,">$output_file"))
      {
	#Report an error and iterate if there was an error
	error("Unable to open output file: [$output_file].\n",$!)
          unless($local_quiet);
	$status = 0;
      }
    else
      {
	$main::open_handles->{$file_handle}->{FILE}   = $output_file;
	$main::open_handles->{$file_handle}->{QUIET}  = $local_quiet;
	$main::open_handles->{$file_handle}->{SELECT} = $select;

	if($local_dry_run)
	  {
	    my $encompassing_dir = $output_file;
	    $encompassing_dir =~ s/[^\/]+$//;
	    $encompassing_dir =~ s%/%%;
	    $encompassing_dir = '.' unless($encompassing_dir =~ /./);

	    if(-e $output_file && !(-w $output_file))
	      {error("Output file exists and is not writable: ",
		     "[$output_file].") unless($local_quiet)}
	    elsif(-e $encompassing_dir && !(-w $encompassing_dir))
	      {error("Encompassing directory of output file: ",
		     "[$output_file] exists and is not writable.")
                 unless($local_quiet)}
	    else
	      {verbose("[$output_file] Opened output file.")
                 unless($local_quiet)}

	    #This cleans up the global hashes of file handles
	    closeOut($file_handle);

	    return($status);
	  }

	verbose("[$output_file] Opened output file.") unless($local_quiet);

	#Store info about the run as a comment at the top of the output
	print $file_handle (getHeader()) if($local_header);

	#Select the output file handle
	select($file_handle) if($select);
      }

    #If we succeeded and there was a selection made, clean up other selection
    #states (should only be one, but just to be safe, we'll check all possible)
    if($status && $select)
      {
	#Mark any other file handles as not selected
	map {$main::open_handles->{$_}->{SELECT} = 0}
	  grep {$_ ne $file_handle && $main::open_handles->{$_}->{SELECT}}
	    keys(%{$main::open_handles});
      }

    return($status);
  }

#Globals used: $dry_run
sub closeOut
  {
    my $file_handle   = $_[0];
    my $status        = 1;
    my $local_dry_run = defined($dry_run) ? $dry_run : 0;

    return($status) unless(defined($file_handle));

    #If we're printing to STDOUT, don't close - just issue a checkpoint message
    if($file_handle eq *STDOUT)
      {
	verbose("[STDOUT] Output checkpoint.  ",
		"Time taken: [",markTime(),' Seconds].')
	  if(!exists($main::open_handles->{$file_handle}) ||
	     !$main::open_handles->{$file_handle}->{QUIET});
      }
    elsif(tell($file_handle) == -1)
      {
	error("File handle submitted was not open.");
	$status = 0;

	if(exists($main::open_handles->{$file_handle}))
	  {
	    warning("Untracking previously closed (or unopened) file handle: ",
		    "[$main::open_handles->{$file_handle}->{FILE}].");

	    my $selected_handle = select();
	    #Confirm that this handle was/is supposed to have been selected
	    #before selecting STDOUT - if it actually is selected, but is not
	    #tracked as such, then they're doing things manually - do not
	    #interfere by selecting STDOUT.
	    if($main::open_handles->{$file_handle}->{SELECT} &&
	       $selected_handle eq $file_handle && $selected_handle ne *STDOUT)
	      {
		#Select standard out
		select(STDOUT);
	      }

	    delete($main::open_handles->{$file_handle});
	  }
	else
	  {
	    my $selected_handle = select();
	    #Confirm that this handle was/is selected before selecting STDOUT
	    if($selected_handle eq $file_handle && $selected_handle ne *STDOUT)
	      {
		#Select standard out
		select(STDOUT);
	      }
	  }
      }
    else
      {
	if(!$local_dry_run)
	  {
	    my $selected_handle = select();

	    #Confirm that this handle was/is selected before selecting STDOUT
	    if($selected_handle eq $file_handle && $file_handle ne *STDOUT)
	      {
		#Select standard out
		select(STDOUT);
	      }

	    #Close the output file handle
	    close($file_handle);
	  }

	verbose("[$main::open_handles->{$file_handle}->{FILE}] Output file ",
		"done.  Time taken: [",markTime(),' Seconds].')
	  if(!exists($main::open_handles->{$file_handle}) ||
	     !$main::open_handles->{$file_handle}->{QUIET});

	delete($main::open_handles->{$file_handle});
      }

    return($status);
  }

#Globals used: $force, $default_stub
sub openIn
  {
    my $file_handle   = $_[0];
    my $input_file    = $_[1];
    my $local_quiet   = (scalar(@_) >= 3 && defined($_[2]) ? $_[2] : 0);
    my $status        = 1;     #Returns true if successful or $force > 1
    my $local_dry_run = defined($dry_run) ? $dry_run : 0;

    if(!defined($input_file))
      {
	error("Invalid input file submitted.  File name undefined.");
	$status = 0;
      }
    else
      {
	#Open the input file
	if(!open($file_handle,$input_file))
	  {
	    #Report an error and iterate if there was an error
	    error("Unable to open input file: [$input_file].  $!");

	    #If force is supplied less than twice, set status to
	    #unsuccessful/false, otherwise pretend everything's OK
	    $status = 0 if(!defined($force) || $force < 2);
	  }
	else
	  {
	    verbose('[',($input_file eq '-' ?
			 (defined($default_stub) ? $default_stub : 'STDIN') :
			 $input_file),
		    '] Opened input file.') if($local_quiet);

	    $main::open_handles->{$file_handle}->{FILE}  = $input_file;
	    $main::open_handles->{$file_handle}->{QUIET} = $local_quiet;

	    closeIn($file_handle) if($local_dry_run);
	  }
      }

    return($status);
  }

#Globals used: $default_stub
sub closeIn
  {
    my $file_handle = $_[0];

    #Close the input file handle
    close($file_handle);

    verbose('[',($main::open_handles->{$file_handle}->{FILE} eq '-' ?
		 (defined($default_stub) ? $default_stub : 'STDIN') :
		 $main::open_handles->{$file_handle}->{FILE}),
	    '] Input file done.  Time taken: [',markTime(),
	    ' Seconds].') if(!exists($main::open_handles->{$file_handle}) ||
			     !$main::open_handles->{$file_handle}->{QUIET});

    delete($main::open_handles->{$file_handle});
  }

#Note: Creates a surrounding reference to the submitted array if called in
#scalar context and there are more than 1 elements in the parameter array
sub copyArray
  {
    if(scalar(grep {ref(\$_) ne 'SCALAR' && ref($_) ne 'ARRAY'} @_))
      {
	error("Invalid argument - not an array of scalars.");
	quit(-19);
      }
    my(@copy);
    foreach my $elem (@_)
      {push(@copy,(defined($elem) && ref($elem) eq 'ARRAY' ?
		   [copyArray(@$elem)] : $elem))}
    debug({LEVEL => -99},"Returning array copy of [",
	  join(',',map {defined($_) ? $_ : 'undef'} @copy),"].");
    return(wantarray ? @copy : (scalar(@copy) > 1 ? [@copy] : $copy[0]));
  }

#Globals used: $defaults_dir
sub getUserDefaults
  {
    my $remove_quotes = defined($_[0]) ? $_[0] : 0;
    my $script        = $0;
    $script           =~ s/^.*\/([^\/]+)$/$1/;
    my $defaults_file = (defined($defaults_dir) ?
			 $defaults_dir : (sglob('~/.rpst'))[0]) . "/$script";
    my $return_array  = [];

    if(open(DFLTS,$defaults_file))
      {
	@$return_array = map {chomp;if($remove_quotes){s/^['"]//;s/["']$//}$_}
	  <DFLTS>;
	close(DFLTS);
      }
    elsif(-e $defaults_file)
      {error("Unable to open user defaults file: [$defaults_file].  $!")}

    debug("User defaults retrieved from [$defaults_file]: [",
	  join(' ',@$return_array),"].");

    return(wantarray ? @$return_array : $return_array);
  }

#Globals used: $defaults_dir
sub saveUserDefaults
  {
    my $argv   = $_[0]; #OPTIONAL
    my $status = 1;

    return($status) if(!defined($use_as_default) || !$use_as_default);

    my $orig_defaults = getUserDefaults();

    #Grab defaults from getCommand, because it re-adds quotes & other niceties
    if(!defined($argv))
      {
	$argv = [getCommand(0,1)];
	#Remove the script name
	shift(@$argv);
      }

    my $script        = $0;
    $script           =~ s/^.*\/([^\/]+)$/$1/;
    my $defaults_file = (defined($defaults_dir) ?
			 $defaults_dir : (sglob('~/.rpst'))[0]) . "/$script";

    my $save_argv = [grep {$_ ne '--save-as-default'} @$argv];

    debug({LEVEL => -99},"Defaults dir: [",
	  (defined($defaults_dir) ? $defaults_dir : 'undef'),"].");

    #If the defaults directory does not exist and mkdirs returns an error
    if(defined($defaults_dir) && !(-e $defaults_dir) && !mkdirs($defaults_dir))
      {
	error("Unable to create defaults directory: [$defaults_dir].  $!");
	$status = 0;
      }
    else
      {
	if(open(DFLTS,">$defaults_file"))
	  {
	    print DFLTS (join("\n",@$save_argv));
	    close(DFLTS);
	  }
	else
	  {
	    error("Unable to write to defaults file: [$defaults_file].  $!");
	    $status = 0;
	  }
      }

    if($status)
      {print("Old user defaults: [",join(' ',@$orig_defaults),"].\n",
	     "New user defaults: [",join(' ',getUserDefaults()),"].\n")}
  }

#Globals used: $header
sub getHeader
  {
    return('') if(!defined($header) || !$header);

    my $version_str = getVersion();
    $version_str =~ s/\n(?!#|\z)/\n#/sg;
    $main::header_str = "$version_str\n" .
      '#User: ' . $ENV{USER} . "\n" .
	'#Time: ' . scalar(localtime($^T)) . "\n" .
	  '#Current Directory: ' . $ENV{PWD} . "\n" .
	    '#Command: ' . scalar(getCommand(1)) . "\n\n";

    return($main::header_str);
  }

#This sub takes an array reference (which should initially point to an empty
#array) and a reference to an array containing a series of numbers indicating
#the number of available items to choose from for each position.  It returns,
#in order, an array (the size of the second argument (pool_sizes array))
#containing an as-yet unseen combination of values where each value is selected
#from 1 to the pool size at that position.  E.g. If the pool_sizes array is
#[2,3,1], the combos will be ([1,1,1],[1,2,1],[1,3,1],[2,1,1],[2,2,1],[2,3,1])
#on each subsequent call.  Returns undef when all combos have been generated
sub GetNextIndepCombo
  {
    #Read in parameters
    my $combo      = $_[0];  #An Array of numbers
    my $pool_sizes = $_[1];  #An Array of numbers indicating the range for each
                             #position in $combo

    if(ref($combo) ne 'ARRAY' ||
       scalar(grep {/\D/} @$combo))
      {
	print STDERR ("ERROR:ordered_digit_increment.pl:GetNextIndepCombo:",
		      "The first argument must be an array reference to an ",
		      "array of integers.\n");
	return(0);
      }
    elsif(ref($pool_sizes) ne 'ARRAY' ||
	  scalar(grep {/\D/} @$pool_sizes))
      {
	print STDERR ("ERROR:ordered_digit_increment.pl:GetNextIndepCombo:",
		      "The second argument must be an array reference to an ",
		      "array of integers.\n");
	return(0);
      }

    my $set_size   = scalar(@$pool_sizes);

    #Initialize the combination if it's empty (first one) or if the set size
    #has changed since the last combo
    if(scalar(@$combo) == 0 || scalar(@$combo) != $set_size)
      {
	#Empty the combo
	@$combo = ();
	#Fill it with zeroes
        @$combo = (split('','0' x $set_size));
	#Return true
        return(1);
      }

    my $cur_index = $#{$combo};

    #Increment the last number of the combination if it is below the pool size
    #(minus 1 because we start from zero) and return true
    if($combo->[$cur_index] < ($pool_sizes->[$cur_index] - 1))
      {
        $combo->[$cur_index]++;
        return(1);
      }

    #While the current number (starting from the end of the combo and going
    #down) is at the limit and we're not at the beginning of the combination
    while($combo->[$cur_index] == ($pool_sizes->[$cur_index] - 1) &&
	  $cur_index >= 0)
      {
	#Decrement the current number index
        $cur_index--;
      }

    #If we've gone past the beginning of the combo array
    if($cur_index < 0)
      {
	@$combo = ();
	#Return false
	return(0);
      }

    #Increment the last number out of the above loop
    $combo->[$cur_index]++;

    #For every number in the combination after the one above
    foreach(($cur_index+1)..$#{$combo})
      {
	#Set its value equal to 0
	$combo->[$_] = 0;
      }

    #Return true
    return(1);
  }

#This subroutine returns 2 arrays.  It creates an array of output file names
#and an array of output file stubs from the input file names and the output
#directories (in case the coder wants to handle output file name construction
#on their own).  It checks all the future output files for possible overwrite
#conflicts and checks for existing output files.  It quits if it finds a
#conflict.  It uses the output_modes array to determine whether a conflict
#is actually a conflict or just should be appended to when encountered.  If
#the output mode is split, it tries to avoid conflicting non-aggregating
#output files by joining the input file names with delimiting dots (in the
#order supplied in the stubs array).  It smartly compounds with a single file
#name if that file name is unique, otherwise, it joins all file names.
#ASSUMES that output_modes 2D array is properly populated.
sub makeCheckOutputs
  {
    my $stub_sets          = copyArray($_[0]);#REQUIRED 2D array of stub combos
    my $suffixes           = $_[1]; #OPTIONAL (Requires $_[2])
    my $output_modes       = $_[2];
    my $index_uniq         = [map {{}} @{$stub_sets->[0]}]; #Array of hashes
    my $is_index_unique    = [map {1} @{$stub_sets->[0]}];
    my $delim              = '.';

    debug({LEVEL => -2},"Called.");

    #Build the is_index_unique array
    foreach my $stub_set (@$stub_sets)
      {
	foreach my $type_index (0..$#{$stub_set})
	  {
	    if($#{$index_uniq} < $type_index)
	      {
		error("Critical internal error: type index too big.");
		quit(-25);
	      }
	    #Only interested in stubs with defined values
	    if(defined($stub_set->[$type_index]))
	      {
		if(exists($index_uniq->[$type_index]
			  ->{$stub_set->[$type_index]}))
		  {
		    $is_index_unique->[$type_index] = 0;
		    debug({LEVEL => -99},"Index [$type_index] is not unique");
		  }
		$index_uniq->[$type_index]->{$stub_set->[$type_index]} = 1;
	      }
	    else
	      {$is_index_unique->[$type_index] = 0}
	  }
      }

    #Find the first unique index with defined values if one exists.
    #We'll use it to hopefully make other stubs unique
    my($first_unique_index);
    foreach my $index (0..$#{$is_index_unique})
      {
	if($is_index_unique->[$index])
	  {
	    $first_unique_index = $index;
	    debug({LEVEL => -2},"Unique index: [$index].");
	    last;
	  }
      }

    my $outfiles_sets = [];    #This will be the returned 3D outfiles array
    my $unique_hash   = {};    #This will be the check for outfile uniqueness
                               #$unique_hash->{$outfile}->{$type}->{$aggmode}++
                               #Quit if any file has multiple types or
                               #$unique_hash->{$outfile}->{$type}->{error} > 1

    #For each stub set
    foreach my $stub_set (@$stub_sets)
      {
	push(@$outfiles_sets,[]);
	my $saved_stub_set = copyArray($stub_set);

	#For each file-type/stub index
	foreach my $type_index (0..$#{$stub_set})
	  {
	    push(@{$outfiles_sets->[-1]},[]);

	    debug({LEVEL => -2},"Index $type_index is ",
		  ($is_index_unique->[$type_index] ? '' : 'not '),"unique.");

	    my $name          = $stub_set->[$type_index];
	    my $compound_name = $stub_set->[$type_index];

	    #If output modes is defined, an output mode is set for this type
	    #index, there exists a split output mode, the stubs at this index
	    #are not unique, AND this stub is defined, compound the name
	    if(defined($output_modes) &&
	       defined($output_modes->[$type_index]) &&
	       scalar(grep {defined($_) && $_ eq 'split'}
		      @{$output_modes->[$type_index]}) &&
	       !$is_index_unique->[$type_index] &&
	       defined($stub_set->[$type_index]))
	      {
		debug({LEVEL => -2},
		      "Creating compund name for index $type_index.");
		my $stub = $stub_set->[$type_index];
		$stub =~ s/.*\///;
		my $dir = $stub_set->[$type_index];
		unless($dir =~ s/^(.*\/).*/$1/)
		  {$dir = ''}

		if(defined($first_unique_index))
		  {
		    my $unique_name = $stub_set->[$first_unique_index];
		    $unique_name =~ s/.*\///;

		    #Compound the stub with the unique one in index order

		    #For backward compatibility, change stub in-place
		    if(!defined($output_modes))
		      {$stub_set->[$type_index] = $dir .
			 ($type_index < $first_unique_index ?
			  $stub . $delim . $unique_name :
			  $unique_name . $delim . $stub)}

		    $compound_name = $dir .
		      ($type_index < $first_unique_index ?
		       $stub . $delim . $unique_name :
		       $unique_name . $delim . $stub);
		  }
		else
		  {
		    #Don't worry if not enough files exist to create a unique
		    #compound name.  Uniqueness is checked after compounding.

		    my $tmp_stub = $stub_set->[0];
		    $tmp_stub =~ s/(.*\/).*/$1/;

		    #For backward compatibility, change stub in-place
		    if(!defined($output_modes))
		      {$stub_set->[$type_index] =
			 $tmp_stub . join($delim,
					  map {s/.*\///;$_} grep {defined($_)}
					  @$saved_stub_set)}

		    $compound_name =
		      $tmp_stub . join($delim,
				       map {s/.*\///;$_} grep {defined($_)}
				       @$saved_stub_set);
		  }
		debug({LEVEL => -2},"New stub: [$compound_name].");
	      }

	    debug({LEVEL => -2},"Creating file names.");
	    #Create the file names using the suffixes and compound name (though
	    #note that the compound name might not be compounded)
	    #If the stub is defined
	    if(defined($stub_set->[$type_index]))
	      {
		#If suffixes is defined & there are suffixes for this index
		if(defined($suffixes) && $#{$suffixes} >= $type_index &&
		   defined($suffixes->[$type_index]) &&
		   scalar(@{$suffixes->[$type_index]}))
		  {
		    my $cnt = 0;
		    #For each suffix available for this file type
		    foreach my $suffix (@{$suffixes->[$type_index]})
		      {
			if(!defined($suffix))
			  {
			    push(@{$outfiles_sets->[-1]->[$type_index]},undef);
			    $cnt++;
			    next;
			  }

			#Concatenate the possibly compounded stub and suffix to
			#the new stub set
			push(@{$outfiles_sets->[-1]->[$type_index]},
			     ($output_modes->[$type_index]->[$cnt] eq 'split' ?
			      $compound_name . $suffix : $name . $suffix));

			$unique_hash
			  ->{$outfiles_sets->[-1]->[$type_index]->[-1]}
			    ->{$type_index}
			      ->{$output_modes->[$type_index]->[$cnt]}++;

			$cnt++;
		      }
		  }
	      }
	    else
	      {
		if(defined($suffixes->[$type_index]))
		  {
		    #The stub is added to the new stub set unchanged
		    #For each suffix available for this file type
		    foreach my $suffix (@{$suffixes->[$type_index]})
		      {push(@{$outfiles_sets->[-1]->[$type_index]},undef)}
		  }
	      }
	  }
      }

    #Let's make sure that the suffixes for each type are unique
    if(defined($suffixes))
      {
	debug({LEVEL => -2},"Checking suffixes.");
	my $unique_suffs = {};   #$unique_suffs->{$type}->{$suffix}++
	                         #Quit if $unique_suffs->{$type}->{$suffix} > 1
	my $dupe_suffs   = {};
	foreach my $type_index (0..$#{$suffixes})
	  {
	    foreach my $suffix (grep {defined($_)} @{$suffixes->[$type_index]})
	      {
		$unique_suffs->{$type_index}->{$suffix}++;
		if($unique_suffs->{$type_index}->{$suffix} > 1)
		  {$dupe_suffs->{$type_index + 1}->{$suffix} = 1}
	      }
	  }

	if(scalar(keys(%$dupe_suffs)))
	  {
	    my @report_errs = map {my $k = $_;"$k:" .
				     join(",$k:",keys(%{$dupe_suffs->{$k}}))}
	      keys(%$dupe_suffs);
	    @report_errs = (@report_errs[0..8],'...')
	      if(scalar(@report_errs) > 10);
	    error("The following input file types have duplicate output file ",
		  "suffixes (type:suffix): [",join(',',@report_errs),"].  ",
		  "This is a predicted overwrite situation that can only be ",
		  "surpassed by providing unique suffixes for each file type ",
		  "or by using --force combined with either --overwrite or ",
		  "--skip-existing.");
	    quit(-33);
	  }
      }

    #Now we shall check for uniqueness using unique_hash and the suffixes
    #$unique_hash->{$outfile}->{$type}->{$aggmode}++
    #Quit if any file has multiple types or
    #$unique_hash->{$outfile}->{$type}->{error} > 1
    if(#The unique hash is populated
       scalar(keys(%$unique_hash)) &&
       #If any file has multiple types
       scalar(grep {scalar(keys(%$_)) > 1} values(%$unique_hash)))
      {
	my @report_errs = grep {scalar(keys(%{$unique_hash->{$_}})) > 1}
	  keys(%$unique_hash);
	@report_errs = (@report_errs[0..8],'...')
	  if(scalar(@report_errs) > 10);
	error("The following output files have conflicting file names from ",
	      "different input file types: [",join(',',@report_errs),"].  ",
	      "Please make sure the corresponding similarly named input ",
	      "files output to different directories.  This error may be ",
	      "circumvented by --force and either --overwrite or ",
	      "--skip-existing, but it is heavily discouraged - only use for ",
	      "testing.");
	quit(-34);
      }
    #Quit if $unique_hash->{$outfile}->{$type}->{error} > 1
    elsif(#The unique hash is populated
	  scalar(keys(%$unique_hash)) &&
	  #There exist error modes
	  scalar(grep {$_ eq 'error'} map {@$_} grep {defined($_)}
		 @$output_modes) &&
	  #There exists an output filename duplicate for an error mode outfile
	  scalar(grep {$_ > 1} map {values(%$_)} grep {exists($_->{error})}
		 map {values(%$_)} values(%$unique_hash)))
      {
	my @report_errs =
	  grep {my $k = $_;scalar(grep {exists($_->{error}) && $_->{error} > 0}
				  values(%{$unique_hash->{$k}}))}
	    keys(%$unique_hash);
	@report_errs = (@report_errs[0..8],'...')
	  if(scalar(@report_errs) > 10);
	error("Output file name conflict(s) detected: [",
	      join(',',@report_errs),"].  The output mode for these files is ",
	      "set tocause an error if multiple input files output to the ",
	      "same output file.  There must be a different output ",
	      "file name for each combination of input files.  Please check ",
	      "your input files for duplicates.  This error may be ",
	      "circumvented by --force and either --overwrite or ",
	      "--skip-existing, but it is heavily discouraged - only use for ",
	      "testing.");
	quit(-35);
      }
    #Quit if any of the outfiles created already exist
    else
      {
	my(%exist);
	foreach my $outfile_arrays_combo (@$outfiles_sets)
	  {foreach my $outfile_array (@$outfile_arrays_combo)
	     {foreach my $outfile (@$outfile_array)
		{checkFile($outfile,undef,1,0) || $exist{$outfile}++}}}

	if(scalar(keys(%exist)))
	  {
	    my $report_exist = [scalar(keys(%exist)) > 10 ?
				((keys(%exist))[0..8],'...') : keys(%exist)];
	    error("Output files exist: [",join(',',@$report_exist),
		  "].  Use --overwrite or --skip-existing to continue.");
	    quit(-30);
	  }
      }

    #debug("Unique hash: ",Dumper($unique_hash),"\nOutput modes: ",
    #	  Dumper($output_modes),{LEVEL => -1});
    #debug({LEVEL => -99},"Returning outfiles: ",Dumper($outfiles_sets));

    #While edited the stubs that were sent in in the scope where the call was
    #made, however we're also going to return those stubs concatenated with
    #file suffixes sent in [1:M relationship].  (If no suffixes were provided,
    #this will essentially be the same as the stubs, only with subarrays
    #inserted in.
    return($outfiles_sets,$stub_sets);
  }

sub getMatchedSets
  {
    my $array = $_[0]; #3D array

    debug({LEVEL => -99},"getMatchedSets called");

    #First, create a list of hashes that contain the effective and actual
    #dimension size and the file type index, as well as the 2D array of file
    #names themselves.  The number of rows is the actual and effective first
    #dimension size and the the number of columns is the second dimension size.
    #The number of columns may be variable.  If the number of columns is the
    #same for every row, the effective and actual second dimension size is the
    #same.  If they are different, the actual second dimension size is a series
    #of number of columns for each row and the effective dimension size is as
    #follows: If The numbers of columns across all rows is either 1 or N, the
    #effective second dimension size is N, else it is the series of numbers of
    #columns across each row (a comma-delimited string).  If an array is empty
    #or contains undef, it will be treated as 1x1.

    #When the effective second dimension size is variable, but only contains
    #sizes of 1 & N, then the first element of each row is copied until all
    #rows have N columns.

    #Create an array of hashes that store the dimension sizes and 2D array data
    my $type_container = [];
    #For each file type index
    foreach my $type_index (0..$#{$array})
      {
	#If any rows are empty, create a column containing a single undef
	#member
	foreach my $row (@{$array->[$type_index]})
	  {push(@$row,undef) if(scalar(@$row) == 0)}
	if(scalar(@{$array->[$type_index]}) == 0)
	  {push(@{$array->[$type_index]},[undef])}

	my $first_dim_size = scalar(@{$array->[$type_index]});

	#A hash tracking the number of second dimension sizes
	my $sd_hash = {};

	#A list of the second dimension sizes
	my $second_dim_sizes = [map {my $s=scalar(@$_);$sd_hash->{$s}=1;$s}
				@{$array->[$type_index]}];

	#Ignore second dimension sizes of 1 in determining the effective second
	#dimension size
	delete($sd_hash->{1});

	#Grab the first second dimension size (or it's 1 if none are left)
	my $first_sd_size =
	  scalar(keys(%$sd_hash)) == 0 ? 1 : (keys(%$sd_hash))[0];

	#The effective second dimension size is the first one from above if
	#there's only 1 of them, otherwise it's variable and stored as a comma-
	#delimited string.  Note, if it's a mix of 1 & some dimension N, the
	#effective second dimension size is N.
	my($effective_sd_size);
	if(scalar(keys(%$sd_hash)) == 1 || scalar(keys(%$sd_hash)) == 0)
	  {$effective_sd_size = $first_sd_size}
	else
	  {$effective_sd_size = join(',',@$second_dim_sizes)}

	debug({LEVEL => -98},"Type [$type_index] is $first_dim_size x ",
	      "$effective_sd_size or [$first_dim_size] x ",
	      "[@$second_dim_sizes]");

	#Change each 2D file array into a hash which stores its type index,
	#actual row size(s), effective row sizes, actual column sizes,
	#effective column sizes, and the actual 2D array of file names
	push(@$type_container,
	     {AF   => [$first_dim_size],       #Actual first dimension sizes
	      AS   => $second_dim_sizes,       #Actual second dimension sizes
	      EF   => $first_dim_size,         #Effective first dimension size
	      ES   => $effective_sd_size,      #Effective second dimension size
	      TYPE => $type_index,             #Type of files contained
	      DATA => scalar(copyArray($array->[$type_index]))});
	                                       #2D array of file names
      }

    #Next, we transpose any arrays based on the following criteria.  Assume FxS
    #is the effective first by second dimension sizes and that the type
    #container array is ordered by precedence(/type).  The first array will not
    #be transposed to start off and will be added to a new synced group.  For
    #each remaining array, if effective dimensions match an existing synced
    #group (in order), it is added to that synced group.  If it matches none,
    #it is the first member of a new synced group.  A group's dimensions match
    #if they are exactly the same, if they are reversed but exactly the same,
    #or 1 dimension is size 1 and the other dimension is not size 1 and matches
    #either F or S.  If a matching array's dimensions are reversed (i.e. F1xS1
    #= S2xF2 or (F1=1 and S1!=1 and S1=F2) or (S1=1 and F1!=1 and F1=S2)) and
    #it can be transposed, transpose it, else if a matching array's dimensions
    #are reversed and all the members of the synced group can be transposed,
    #transpose the members of the synced group.  Then the current array is
    #added to it.  Otherwise, the array is added as the first member of a new
    #synced group.  If the second dimension is a mix of sizes 1 & N only and N
    #matches F or S in the synced group, the 1 member is duplicated to match
    #the other dimension (F or S).

    my $synced_groups = [{EF    => $type_container->[0]->{EF},
			  ES    => $type_container->[0]->{ES},
			  AF    => [@{$type_container->[0]->{AF}}],
			  AS    => [@{$type_container->[0]->{AS}}],
			  GROUP => [$type_container->[0]]  #This is a hash like
			                                   #in the type_
			                                   #container array
			 }];

    #eval {use Data::Dumper;1} if($DEBUG < 0);

    #debug("Initial group with default candidate: ",
    #	  Dumper($synced_groups->[-1]->{GROUP}),"There are [",
    #	  scalar(@$type_container),"] types total.",{LEVEL => -99});

    #For every type_hash_index in the type container except the first one
    foreach my $type_hash_index (1..$#{$type_container})
      {
	my $type_hash = $type_container->[$type_hash_index];

	my $found_match = 0;

	my $candidate_ef = $type_hash->{EF};
	my $candidate_es = $type_hash->{ES};
	my $candidate_af = $type_hash->{AF};
	my $candidate_as = $type_hash->{AS};

	debug({LEVEL => -99},
	      "candidate_ef $candidate_ef candidate_es $candidate_es ",
	      "candidate_af @$candidate_af candidate_as @$candidate_as");

	foreach my $group_hash (@$synced_groups)
	  {
	    my $group_ef = $group_hash->{EF};
	    my $group_es = $group_hash->{ES};
	    my $group_af = $group_hash->{AF};
	    my $group_as = $group_hash->{AS};

	    debug({LEVEL => -99},
		  "group_ef $group_ef group_es $group_es group_af @$group_af ",
		  "group_as @$group_as");

	    #If the candidate and group match (each explained in-line below)
	    if(#Either candidate or group is 1x1 (always a match)
	       ($candidate_ef eq '1' && $candidate_es eq '1') ||
	       ($group_ef     eq '1' && $group_es eq '1') ||

	       #Exact or reverse exact match
	       ($candidate_ef eq $group_ef && $candidate_es eq $group_es) ||
	       ($candidate_ef eq $group_es && $candidate_es eq $group_ef) ||

	       #candidate_ef is 1 and candidate_es is not 1 but matches either
	       ($candidate_ef eq '1' && $candidate_es ne '1' &&
		($candidate_es eq $group_es || $candidate_es eq $group_ef)) ||

	       #candidate_es is 1 and candidate_ef is not 1 but matches either
	       ($candidate_es eq '1' && $candidate_ef ne '1' &&
		($candidate_ef eq $group_es || $candidate_ef eq $group_ef)) ||

	       #group_ef is 1 and group_es is not 1 but matches either
	       ($group_ef eq '1' && $group_es ne '1' &&
		($group_es eq $candidate_es || $group_es eq $candidate_ef)) ||

	       #group_es is 1 and group_ef is not 1 but matches either
	       ($group_es eq '1' && $group_ef ne '1' &&
		($group_ef eq $candidate_es || $group_ef eq $candidate_ef)) ||

	       #First dimensions match exactly and each second dimension is
	       #either an exact corresponding match or one of them is a 1
	       ($candidate_ef eq $group_ef &&
		scalar(grep {$group_as->[$_] == $candidate_as->[$_] ||
			       $group_as->[$_] == 1 ||
				 $candidate_as->[$_] == 1}
		       (0..($group_ef - 1))) == $group_ef))
	      {
		$found_match = 1;

		#If the candidate's dimensions are not the same, the group's
		#dimensions are not the same, and the candidate's dimensions
		#are reversed relative to the group, we need to transpose
		#either the candidate or the group.
		if(#Neither the candidate nor group is a square
		   $candidate_ef ne $candidate_es && $group_ef ne $group_es &&
		   #Either the candidate or group is not variable dimension
		   ($candidate_es !~ /,/ || $group_es !~ /,/) &&
		   #The matching dimension is opposite & not size 1
		   (($candidate_ef eq $group_es && $group_es ne '1') ||
		    ($candidate_es eq $group_ef && $group_ef ne '1')))
		  {
		    #We need to transpose either the candidate or group

		    #If the candidate can be transposed
		    if($candidate_es !~ /,/)
		      {
			#Assuming the number of columns varies between 1 & M,
			#fill up the rows of size 1 to match M before
			#transposing. (Won't hurt if they don't)
			foreach my $row (@{$type_hash->{DATA}})
			  {while(scalar(@$row) < $candidate_es)
			     {push(@$row,$row->[0])}}

			debug({LEVEL => -99},"Transposing candidate.");
			@{$type_hash->{DATA}} = transpose($type_hash->{DATA});
			my $tmp = $candidate_ef;
			$candidate_ef = $type_hash->{EF} = $candidate_es;
			$candidate_es = $type_hash->{ES} = $tmp;
			$candidate_af = $type_hash->{AF} =
			  [scalar(@{$type_hash->{DATA}})];
			$candidate_as = $type_hash->{AS} =
			  [map {scalar(@$_)} @{$type_hash->{DATA}}];
		      }
		    #Else if the group can be transposed
		    elsif($group_es !~ /,/)
		      {
			debug({LEVEL => -99},"Transposing group.");
			#For every member of the group (which is a type hash)
			foreach my $member_type_hash (@{$group_hash->{GROUP}})
			  {
			    #Assuming the number of columns varies between 1 &
			    #M, fill up the rows of size 1 to match M before
			    #transposing. (Won't hurt if they don't)
			    foreach my $row (@{$member_type_hash->{DATA}})
			      {while(scalar(@$row) < $group_es)
				 {push(@$row,$row->[0])}}

			    @{$member_type_hash->{DATA}} =
			      transpose($member_type_hash->{DATA});

			    #Update the type hash's metadata
			    my $tmp = $member_type_hash->{EF};
			    $member_type_hash->{EF} = $member_type_hash->{ES};
			    $member_type_hash->{ES} = $tmp;
			    $member_type_hash->{AF} =
			      [scalar(@{$member_type_hash->{DATA}})];
			    $member_type_hash->{AS} =
			      [map {scalar(@$_)} @{$member_type_hash->{DATA}}];
			  }

			#Update the group metadata (using the first member of
			#the group)
			my $tmp = $group_ef;
			$group_ef = $group_hash->{EF} = $group_es;
			$group_es = $group_hash->{ES} = $tmp;
			$group_af = $group_hash->{AF} =
			  [scalar(@{$group_hash->{GROUP}->[0]->{DATA}})];
			$group_as = $group_hash->{AS} =
			  [map {scalar(@$_)}
			   @{$group_hash->{GROUP}->[0]->{DATA}}];
		      }
		    else
		      {
			error("Critical internal error: Transpose not ",
			      "possible.  This should not be possible.");
			quit(-26);
		      }
		  }

		#Anything that needed transposed has now been transposed, so
		#now we need to even things up by filling any 1-dimensional
		#arrays to match their 2D matches.

		debug({LEVEL => -99},
		      "Add rows if(candidate_ef eq '1' && group_ef ne '1' && ",
		      "group_es ne '1'): if($candidate_ef eq '1' && ",
		      "$group_ef ne '1' && $group_es ne '1')");

		#If we need to add any rows to the candidate
		if($candidate_ef eq '1' && $group_ef ne '1')
		  {
		    debug({LEVEL => -99},"Adding rows to candidate.");
		    foreach(2..$group_ef)
		      {push(@{$type_hash->{DATA}},
			    [@{copyArray($type_hash->{DATA}->[0])}])}

		    #Update the metadata
		    $candidate_ef = $type_hash->{EF} = $group_ef;
		    #The effective second dimension size did not change
		    $candidate_af = $type_hash->{AF} = [$group_ef];
		    $candidate_as = $type_hash->{AS} =
		      [map {scalar(@$_)} @{$type_hash->{DATA}}];
		  }

		debug({LEVEL => -99},
		      "Add columns if(candidate_es eq '1' && group_es ne ",
		      "'1': if($candidate_es eq '1' && $group_es ne '1')");

		#If we need to add any columns to the candidate
		my $col_change = 0;
		foreach my $i (0..$#{$group_as})
		  {
		    my $num_cols = $group_as->[$i];
		    my $row = $type_hash->{DATA}->[$i];
		    while(scalar(@$row) < $num_cols)
		      {
			$col_change = 1;
			push(@$row,$row->[0]);
		      }
		  }
		if($col_change)
		  {
		    debug({LEVEL => -99},"Added columns to candidate.");
		    #Update the metadata
		    #The effective first dimension size did not change
		    $candidate_es = $type_hash->{ES} = $group_es;
		    #The actual first dimension size did not change
		    $candidate_as = $type_hash->{AS} =
		      [map {scalar(@$_)} @{$type_hash->{DATA}}];
		  }
		#If we need to add any rows to the group
		if($group_ef eq '1' && $candidate_ef ne '1')
		  {
		    debug({LEVEL => -99},"Adding rows to group.");
		    foreach my $member_type_hash (@{$group_hash->{GROUP}})
		      {
			#Copy the first row up to the effective first
			#dimension size of the candidate
			foreach(2..$candidate_ef)
			  {push(@{$member_type_hash->{DATA}},
				[@{copyArray($member_type_hash->{DATA}
					     ->[0])}])}

			#Update the member metadata
			$member_type_hash->{EF} = $candidate_ef;
			#Effective second dimension size did not change
			$member_type_hash->{AF} = [$candidate_ef];
			$member_type_hash->{AS} =
			  [map {scalar(@$_)} @{$member_type_hash->{DATA}}];
		      }

		    #Update the group metadata
		    $group_ef = $group_hash->{EF} = $candidate_ef;
		    #Effective second dimension size did not change
		    $group_af = $group_hash->{AF} =
		      [scalar(@{$group_hash->{GROUP}->[0]->{DATA}})];
		    #The actual second dimension size could be different if the
		    #candidate has a variable second dimension size
		    $group_as = $group_hash->{AS} =
		      [map {scalar(@$_)} @{$group_hash->{GROUP}->[0]->{DATA}}];
		  }

		#If we need to add any columns to the group
		$col_change = 0;
		foreach my $member_type_hash (@{$group_hash->{GROUP}})
		  {
		    foreach my $i (0..$#{$candidate_as})
		      {
			my $num_cols = $candidate_as->[$i];
			my $row = $member_type_hash->{DATA}->[$i];
			while(scalar(@$row) < $num_cols)
			  {
			    $col_change = 1;
			    push(@$row,$row->[0]);
			  }
		      }

		    if($col_change)
		      {
			#Update the member metadata
			#The effective first dimension size did not change
			$member_type_hash->{ES} = $candidate_es;
			#The actual first dimension size did not change
			$member_type_hash->{AS} =
			  [map {scalar(@$_)} @{$member_type_hash->{DATA}}];
		      }
		    else #Assume everything in a group is same dimensioned
		      {last}
		  }

		if($col_change)
		  {
		    debug({LEVEL => -99},"Added columns to group.");
		    #Update the metadata
		    #The effective first dimension size did not change
		    $group_es = $group_hash->{ES} = $candidate_es;
		    #The actual first dimension size did not change
		    $group_as = $group_hash->{AS} =
		      [map {scalar(@$_)} @{$group_hash->{GROUP}->[0]->{DATA}}];
		  }

		#Put this candidate in the synced group
		push(@{$group_hash->{GROUP}},$type_hash);

		#debug({LEVEL => -99},"Group after adding candidate: ",
		#      Dumper($group_hash->{GROUP}));

		#We stop when we find a match so that we don't put this
		#candidate in multiple synced groups
		last;
	      }
	  }

	unless($found_match)
	  {
	    #Create a new synced group
	    push(@$synced_groups,{EF    => $candidate_ef,
				  ES    => $candidate_es,
				  AF    => $candidate_af,
				  AS    => $candidate_as,
				  GROUP => [$type_hash]});

	    #debug({LEVEL => -99},"New group after adding candidate: ",
	    #	  Dumper($synced_groups->[-1]->{GROUP}));
	  }
      }

    #debug({LEVEL => -99},"Synced groups contains [",Dumper($synced_groups),
    #	  "].");

    #Now I have a set of synced groups, meaning every hash in the group has the
    #same dimensions described by the group's metadata.  However, I don't need
    #that metadata anymore, so I can condense the groups into 1 big array of
    #type hashes and all I need from those is the TYPE (the first index into
    #$array) and the DATA (The 2D array of files).

    #Each group has F * S paired combos.  In order to generate all possible
    #combinations, I need to string them along in a 1 dimensional array

    my $flattened_groups = []; #Each member is an unfinished combo (a hash with
                               #2 keys: TYPE & ITEM, both scalars

    foreach my $synced_group (@$synced_groups)
      {
	push(@$flattened_groups,[]);
	foreach my $row_index (0..($synced_group->{EF} - 1))
	  {
	    foreach my $col_index (0..($synced_group->{AS}->[$row_index] - 1))
	      {
		my $unfinished_combo = [];

		#foreach type hash in GROUP, add the item at row/col index to a
		#combo
		foreach my $type_hash (@{$synced_group->{GROUP}})
		  {
		    debug({LEVEL => -99},"ITEM should be type '': [",
			  ref($type_hash->{DATA}->[$row_index]->[$col_index]),
			  "].");

		    push(@$unfinished_combo,
			 {TYPE => $type_hash->{TYPE},
			  ITEM => $type_hash->{DATA}->[$row_index]
			  ->[$col_index]});
		  }

		push(@{$flattened_groups->[-1]},$unfinished_combo);
	      }
	  }
      }

    #debug({LEVEL => -99},"Flattened groups contains: [",
    #	  Dumper($flattened_groups),"].");

    my $combos = [];
    my $combo  = [];
    while(GetNextIndepCombo($combo,
			    [map {scalar(@$_)} @$flattened_groups]))
      {
	#The index of combo items corresponds to the index of flattened_groups
	#The values of combo correspond to the index into the array member of
	#flattened_groups

	#Construct this combo from the unfinished combos
	my $finished_combo = [];
	foreach my $outer_index (0..$#{$combo})
	  {
	    my $inner_index = $combo->[$outer_index];

	    push(@$finished_combo,
		 @{$flattened_groups->[$outer_index]->[$inner_index]});
	  }

	#Check the finished combo to see that it contains 1 file of each type
	my $check = {map {$_ => 0} (0..$#{$array})};
	my $unknown = {};
	foreach my $type_index (map {$_->{TYPE}} @$finished_combo)
	  {
	    if(exists($check->{$type_index}))
	      {$check->{$type_index}++}
	    else
	      {$unknown->{$type_index}++}
	  }
	my @too_many = grep {$check->{$_} > 1} keys(%$check);
	if(scalar(@too_many))
	  {
	    error("Critical Internal error: Bad Option Combo.  These option ",
		  "types had more than 1 value: [",join(',',@too_many),
		  "].  Use --force to include all combos by attempting to ",
		  "repair it.");

	    #Jump to the next iteration unless the user chose to force it
	    next if(!defined($force) || !$force);

	    #If they force it, try to repair by eliminating extra ones
	    my $fixed_fin_combo = [];
	    my $done = {};
	    foreach my $hash (@$finished_combo)
	      {
		next if(exists($done->{$hash->{TYPE}}));
		$done->{$hash->{TYPE}} = 1;
		push(@$fixed_fin_combo,$hash);
	      }
	    @$finished_combo = @$fixed_fin_combo;
	  }
	my @missing = grep {$check->{$_} == 0} keys(%$check);
	if(scalar(@missing))
	  {
	    error("Critical Internal error: Bad Option Combo.  These option ",
		  "types were missing: [",join(',',@missing),
		  "].  Use --force to include all combos by attempting to ",
		  "repair it.");

	    next if(!defined($force) || !$force);

	    #If they force it, try to repair by adding undefs
	    foreach my $type_index (@missing)
	      {push(@$finished_combo,{TYPE => $type_index,ITEM => undef})}
	  }
	if(scalar(keys(%$unknown)))
	  {
	    error("Critical Internal error: Bad Option Combo.  These option ",
		  "types are unknown: [",join(',',keys(%$unknown)),
		  "].  Use --force to include all combos by attempting to ",
		  "repair it.");

	    next if(!defined($force) || !$force);

	    #If they force it, try to repair by eliminating unknowns
	    my $fixed_fin_combo = [];
	    foreach my $hash (@$finished_combo)
	      {push(@$fixed_fin_combo,$hash)
		 unless(exists($unknown->{$hash->{TYPE}}))}
	    @$finished_combo = @$fixed_fin_combo;
	  }

	#Save the combo to return it
	push(@$combos,
	     [map {$_->{ITEM}}
	      sort {$a->{TYPE} <=> $b->{TYPE}} @$finished_combo]);
      }

    #debug({LEVEL => -99},"getMatchedSets returning combos: [",
    #	  Dumper($combos),"].");

    return(wantarray ? @$combos : $combos);
  }

#This subroutine is spcifically for use with the '<>' Getopt::Long operator
#(which catches flagless options) when used to capture files.  Since all
#unknown options go here, this sub watches for values that do not exist as
#files and begin with a dash followed by a non-number (to be rather forgiving
#of stub usages).  It just issues a warning, but if in strict mode, it will
#call quit.
sub checkFileOpt
  {
    my $alleged_file = $_[0];
    my $strict       = defined($_[1]) ? $_[1] : 0;
    if($alleged_file =~ /^-\D/ && !(-e $alleged_file))
      {
	if($strict)
	  {
	    error("Unknown option: [$alleged_file].");
	    quit(-31);
	  }
	else
	  {warning("Potentially unknown option assumed to be a file name: ",
		   "[$alleged_file].")}
      }
  }

sub processDefaultOptions
  {
    my $outfiles_defined = $_[0];

    #Set defaults if not defined - assumes command line has already been parsed
    $default_stub        = 'STDIN' unless(defined($default_stub));
    $DEBUG               = 0       unless(defined($DEBUG));
    $quiet               = 0       unless(defined($quiet));
    $dry_run             = 0       unless(defined($dry_run));
    $help                = 0       unless(defined($help));
    $version             = 0       unless(defined($version));
    $use_as_default      = 0       unless(defined($use_as_default));
    $skip_existing       = 0       unless(defined($skip_existing));
    $overwrite           = 0       unless(defined($overwrite));
    $verbose             = 0       unless(defined($verbose));
    $force               = 0       unless(defined($force));
    $header              = 0       unless(defined($header));
    $output_mode         = 'error' unless(defined($output_mode));
    $extended            = 0       unless(defined($extended));
    $error_limit_default = 5       unless(defined($error_limit_default));
    $error_limit         = $error_limit_default unless(defined($error_limit));
    $defaults_dir        =(sglob('~/.rpst'))[0] unless(defined($defaults_dir));
    $preserve_args       = [@ARGV]   unless(defined($preserve_args));
    $created_on_date     = 'UNKNOWN' unless(defined($created_on_date));
    $software_version_number = 'UNKNOWN'
      unless(defined($software_version_number));

    #If pipeline mode is not defined and I know it will be needed, guess -
    #otherwise, do it lazily (in the warning or error subs) because pgrep &
    #lsof can be slow sometimes
    if(!defined($pipeline_mode) && ($verbose || $DEBUG))
      {$pipeline_mode = inPipeline()}

    #Now that all the vars are set, flush the buffer if necessary
    flushStderrBuffer();

    #If there's anything in the stderr buffer, it will get emptied from
    #verbose calls below.

    #Print the usage if there are no non-user-default arguments (or it's just
    #the extended flag) and no files directed or piped in
    if((scalar(@$preserve_args) == 0 ||
	(scalar(@$preserve_args) == 1 &&
	 $preserve_args->[0] eq '--extended')) &&
       isStandardInputFromTerminal())
      {
	usage(0);
	quit(0);
      }

    #Error-check for mutually exclusive flags supplied together
    if(scalar(grep {$_} ($use_as_default,$help,$version)) > 1)
      {
	error("--help, --version & --save-as-default are mutually exclusive.");
	quit(-3);
      }

    #If the user has asked for help, call the help subroutine & quit
    if($help)
      {
	help($extended);
	quit(0);
      }

    #If the user has asked for the software version, print it & quit
    if($version)
      {
	print(getVersion(),"\n");
	quit(0);
      }

    #If the user has asked to save the options, save them & quit
    if($use_as_default)
      {
	saveUserDefaults() && quit(0);
	quit(-4);
      }

    #Check validity of verbosity options
    if($quiet && ($verbose || $DEBUG))
      {
	$quiet = 0;
	error('--quiet is mutually exclusive with both --verbose & --debug.');
	quit(-5);
      }

    #Check validity of existing outfile options
    if($skip_existing && $overwrite)
      {
	error('--overwrite & --skip-existing are mutually exclusive.');
	quit(-6);
      }

    #Warn users when they turn on verbose and output is to the terminal
    #(implied by no outfile suffix & no redirect out) that verbose messages may
    #be messy
    if($verbose && !$outfiles_defined && isStandardOutputToTerminal())
      {warning('You have enabled --verbose, but appear to be outputting to ',
	       'the  terminal.  Verbose messages may interfere with ',
	       'formatting of terminal output making it difficult to read.  ',
	       'You may want to either turn verbose off, redirect output to ',
	       'a file, or supply output files by other means.')}

    if($dry_run)
      {
	#It only makes sense to do a dry run in either verbose or debug mode
	$verbose = 1 unless($verbose || $DEBUG);
	verbose('Starting dry run.');
      }

    verbose('Run conditions: ',scalar(getCommand(1)));
    verbose("Verbose level:  [$verbose].");
    verbose('Header:         [on].')           if($header);
    verbose("Debug level:    [$DEBUG].")       if($DEBUG);
    verbose("Force level:    [$force].")       if($force);
    verbose("Overwrite mode: [$overwrite].")   if($overwrite);
    verbose('Skip mode:      [on].')           if($skip_existing);
    verbose("Dry run level:  [$dry_run].")     if($dry_run);
    verbose("Output mode:    [$output_mode].") if($output_mode ne 'error');
    verbose("Error level:    [$error_limit].") if($error_limit !=
						  $error_limit_default);
  }

sub flushStderrBuffer
  {
    #Use the local_force parameter to flush even if the required flags are not
    #defined
    my $local_force = defined($_[0]) ? $_[0] : 0;

    #Return if there is nothing in the buffer
    return(0) if(!defined($main::stderr_buffer));

    #Return if any 1 of the variables controlling these methods is not defined
    #and we're not in force mode
    return(0) if(!$local_force &&
		 (!defined($verbose) || !defined($quiet) || !defined($DEBUG) ||
		  !defined($error_limit)));

    my $debug_num         = 0;
    my $replace_debug_num = 0;
    foreach my $message_array (@{$main::stderr_buffer})
      {
	if(ref($message_array) ne 'ARRAY' || scalar(@$message_array) < 3)
	  {print STDERR ("ERROR: Invalid message found in standard error ",
			 "buffer.  Must be an array with at least 3 ",
			 "elements, but ",
			 (ref($message_array) eq 'ARRAY' ?
			  "only [" . scalar(@$message_array) .
			  "] elements were present." :
			  "a [" . ref($message_array) .
			  "] was sent in instead."))}

	my($type,$level,$message) = @$message_array;

	if($type eq 'verbose')
	  {print STDERR ($message) if(!defined($verbose) || $level == 0 ||
				      ($level < 0 && $verbose <= $level) ||
				      ($level > 0 && $verbose >= $level))}
	elsif($type eq 'debug')
	  {
	    if(!defined($DEBUG) || $level == 0  ||
	       ($level < 0 && $DEBUG <= $level) ||
	       ($level > 0 && $DEBUG >= $level))
	      {
		if($replace_debug_num)
		  {$message =~ s/^DEBUG\d+/DEBUG$debug_num/}
		if($debug_num == 0 && $message =~ /^DEBUG(\d+)/)
		  {$debug_num = $1}
		print STDERR ($message);
		$debug_num++;
	      }
	    elsif($debug_num == 0 && $message =~ /^DEBUG(\d+)/)
	      {
		my $tnum = $1;
		if($tnum == 1)
		  {$debug_num = 1}
		$replace_debug_num = 1;
	      }
	    else
	      {$replace_debug_num = 1}
	  }
	elsif($type eq 'error' || $type eq 'warning')
	  {
	    my($leader);
	    if(scalar(@$message_array) < 4)
	      {
		#Print the error without using the error function so as to
		#avoid a potential infinite loop.
		print STDERR ("ERROR: Parameter array too small.  Must ",
			      "contain at least 4 elements, but it has [",
			      scalar(@$message_array),"].\n");
		$leader = '';
	      }
	    else
	      {$leader = $message_array->[3]}

	    #Skip this one if it is above the error_limit
	    next if(defined($error_limit) && $level > $error_limit);

	    #Notify when going above the error limit
	    $message .=
	      join('',($leader,"NOTE: Further ",
		       ($type eq 'error' ? 'error': "warning"),"s of this ",
		       "type will be suppressed.\n$leader",
		       "Set --error-type-limit to 0 to turn off error ",
		       "suppression\n"))
		if(defined($error_limit) && $level == $error_limit);

	    print STDERR ($message) if(!defined($quiet) || !$quiet);
	  }
	else
	  {
	    #Print the error without using the error function so as to avoid a
	    #potential infinite loop if error() ever sends an invalid type.
	    print STDERR ("ERROR: Invalid type found in standard error ",
			  "buffer: [$type].\n");
	  }
      }

    if($replace_debug_num)
      {$main::debug_number = $debug_num - 1}

    if($local_force &&
       (!defined($verbose) || !defined($quiet) || !defined($DEBUG) ||
	!defined($error_limit)))
      {print STDERR ('Force-flushed the STDERR buffer.  To make this ',
		     'unnecessary, define these variables in main: ',
		     '[$verbose, $quiet, $DEBUG, $error_limit].',"\n")}

    undef($main::stderr_buffer);
  }

#This subroutine guesses whether this script is running with concurrent or
#serially run siblings (i.e. in a script).  It uses pgrep and lsof.  Cases
#where the script is intended to return true: 1. when the script is being piped
#to or from another command (i.e. not a file). 2. when the script is being run
#from inside another script.  In both cases, it is useful to know so that
#messages on STDERR can be prepended with the script name so that the user
#knows the source of any message
sub inPipeline
  {
    my $ppid = getppid();
    my $siblings = `pgrep -P $ppid`;

    #Return true if any sibling processes were detected
    return(1) if($siblings =~ /\d/);

    #Find out what file handles the parent process has open
    my $parent_data = `lsof -w -b -p $ppid`;

    #Return true if the parent has a read-only handle open on a regular file
    #(implying it's reading a script - the terminal/shell does a read/write
    #(mode 'u'))
    return(1) if($parent_data =~ /\s+\d+r\s+REG\s+/);

    return(0);
  }

##
## This subroutine prints a description of the script and it's input and output
## files.
##
#Globals used: $software_version_number, $created_on_date
sub help
  {
    my $script   = $0;
    my $advanced = $_[0];
    my $lmd = localtime((stat($script))[9]);
    $script =~ s/^.*\/([^\/]+)$/$1/;

    #$software_version_number  - global
    $software_version_number = 'UNKNOWN'
      if(!defined($software_version_number));

    #$created_on_date - global
    $created_on_date = 'UNKNOWN' if(!defined($created_on_date) ||
				    $created_on_date eq 'DATE HERE');

    #Print a description of this program
    print << "end_print";

$script version $software_version_number
Copyright 2015
Robert W. Leach
Created: $created_on_date
Last Modified: $lmd
Princeton University
Carl Icahn Laboratory
Lewis Sigler Institute for Integrative Genomics
Bioinformatics Group
Room 133A
Princeton, NJ 08544
rleach\@genomics.princeton.edu

* WHAT IS THIS: DESCRIBE THE PROGRAM HERE

* INPUT FORMAT: DESCRIBE INPUT FILE FORMAT AND GIVE EXAMPLES HERE

* OUTPUT FORMAT: DESCRIBE OUTPUT FORMAT HERE

end_print

    if($advanced)
      {
	my $header = '                 ' .
	  join("\n                 ",split(/\n/,getHeader()));

	print << "end_print";
* HEADER FORMAT: Unless --noheader is supplied or STANDARD output is going to
                 the terminal (and not redirected into a file), every output
                 file, including output to standard out, will get a header that
                 is commented using the '#' character (i.e. each line of the
                 header will begin with '#').  The format of the standard
                 header looks like this:

$header

                 The header is important for 2 reasons:

                 1. It records information about how the file was created: user
                    name, time, script version information, and the command
                    line that was used to create it.

                 2. The header is used to confirm that a file inside a
                    directory that is to be output to (using --outdir) was
                    created by this script before deleting it when in overwrite
                    mode.  See OVERWRITE PROTECTION below.

* OVERWRITE PROTECTION: This script prevents the over-writing of files (unless
                        --overwrite is provided).  A check is performed for
                        pre-existing files before any output is generated.  It
                        will even check if future output files will be over-
                        written in case two input files from different
                        directories have the same name and a common --outdir.
                        Furthermore, before output starts to a given file, a
                        last-second check is performed in case another program
                        or script instance is competing for the same output
                        file.  If such a case is encountered, an error will be
                        generated and the file will always be skipped.

                        Directories: When --outdir is supplied with
                        --overwrite, the directory and its contents will not be
                        deleted.  If you would like an output directory to be
                        automatically removed, supply --overwrite twice on the
                        command line.  The directory will be removed, but only
                        if all of the files inside it can be confirmed to have
                        been created by a previous run of this script.  For
                        this, headers are required to be in the files (i.e. the
                        previous run must not have included the --noheader
                        flag.  This requirement ensures that it is very
                        unlikely to accidentally delete anything that is not
                        intended to have been deleted.  If a directory cannot
                        be emptied, the script will proceed with a warning
                        about any files in the output directory it could not
                        clean out.

                        Note that individual files bearing the same name as a
                        current output file will be overwritten regardless of a
                        header.

* ADVANCED FILE I/O FEATURES:

Sets of input files, each with different output directories can be supplied.
Supply each file set with an additional -i (or --input-file) flag.  Wrap each
set of files in quotes and separate them with spaces.

Output directories (--outdir) can be supplied multiple times in the same order
so that each input file set can be output into a different directory.  If the
number of files in each set is the same, you can supply all output directories
as a single set instead of each having a separate --outdir flag.

Examples:

  $0 -i 'a b c' --outdir '1' -i 'd e f' --outdir '2'

    Resulting file sets: 1/a,b,c  2/d,e,f

  $0 -i 'a b c' -i 'd e f' --outdir '1 2 3'

    Resulting file sets: 1/a,d  2/b,e  3/c,f

If the number of files per set is the same as the number of directories in 1
set are the same, this is what will happen:

  $0 -i 'a b' -i 'd e' --outdir '1 2'

    Resulting file sets: 1/a,d  2/b,e

NOT this: 1/a,b 2/d,e  To do this, you must supply the --outdir flag for each
set, like this:

  $0 -i 'a b' -i 'd e' --outdir '1' --outdir '2'

Other examples:

  $0 -i 'a b c' -i 'd e f' --outdir '1 2'

    Result: 1/a,b,c  2/d,e,f

  $0 -i 'a b c' --outdir '1 2 3' -i 'd e f' --outdir '4 5 6'

    Result: 1/a  2/b  3/c  4/d  5/e  6/f

If this script was modified to handle multiple types of files that must be
processed together, the files which are associated with one another will be
associated in the same manner as the output directories above.  Basically, if
the number of files or sets of files match, they will be automatically
associated in the order in which they were provided on the command line.

end_print
      }

    return(0);
  }

##
## This subroutine prints a usage statement in long or short form depending on
## whether "no descriptions" is true.
##
#Globals used: $extended
sub usage
  {
    my $error_mode     = $_[0]; #Don't print full usage in error mode
    my $local_extended = scalar(@_) > 1 && defined($_[1]) ? $_[1] :
      (defined($extended) ? $extended : 0);

    my $script = $0;
    $script =~ s/^.*\/([^\/]+)$/$1/;

    #Grab the first version of each option from the global GetOptHash
    my $options =
      ($error_mode ? '[' .
       join('] [',
	    grep {$_ ne '-i'}           #Remove REQUIRED params
	    map {my $key=$_;            #Save the key
		 $key=~s/\|.*//;        #Remove other versions
		 $key=~s/(\!|=.|:.)$//; #Remove trailing getopt stuff
		 $key = (length($key) > 1 ? '--' : '-') . $key;} #Add dashes
	    grep {$_ ne '<>'}           #Remove the no-flag parameters
	    keys(%$GetOptHash)) .
       ']' : '[...]');

    print("\n$script -i \"input file(s)\" $options\n",
	  (!$local_extended ? '' :
	   "$script -i \"outfile_stub\" $options < input_file\n"),
	  "\n");

    if($error_mode)
      {print("Run with no options for usage.\n")}
    else
      {
	if(!$local_extended)
	  {
	    print << 'end_print';
     -i                   REQUIRED Input file(s).  See --help for file format.
     -o                   OPTIONAL [stdout] Outfile extension (appended to -i).
     --outdir             OPTIONAL [none] Output directory.  Requires -o.
     --verbose            OPTIONAL Verbose mode.
     --quiet              OPTIONAL Quiet mode.
     --dry-run            OPTIONAL Run without generating output files.
     --version            OPTIONAL Print version.
     --save-as-default    OPTIONAL Save the command line arguments.
     --help               OPTIONAL Print general info and file formats.
     --extended           OPTIONAL Print extended usage/help/version/header.

end_print
	  }
	else #Advanced options/extended usage output
	  {
	    my $defdir = (defined($defaults_dir) ?
			  $defaults_dir : (sglob('~/.rpst'))[0]);
	    $defdir = 'undefined' if(!defined($defdir));
	    print << 'end_print';
     -i,--input-file,     REQUIRED Input file(s).  Space separated, globs OK
     --stdin-stub,--stub*          (e.g. -i "*.text [A-Z].{?,??}.txt").  When
                                   standard input detected, -o has been
                                   supplied, and -i is given only 1 argument,
                                   it will be used as a file name stub for
                                   combining with -o to create the outfile
                                   name.  See --extended --help for file format
                                   and advanced usage examples.
                                   *No flag required.
     -o,--outfile-suffix  OPTIONAL [stdout] Outfile extension appended to -i.
                                   Will not overwrite without --overwrite.
                                   Supplying an empty string will effectively
                                   treat the input file name (-i) as a stub
                                   (may be used with --outdir as well).  When
                                   standard input is detected and no stub is
                                   provided via -i, appends to the string
                                   "STDIN".  Does not replace existing input
                                   file extensions.  Default behavior prints
                                   output to standard out.  See --extended
                                   --help for output file format and advanced
                                   usage examples.
     --outdir             OPTIONAL [none] Directory to put output files.  This
                                   option requires -o.  Default output
                                   directory is the same as that containing
                                   each input file.  Relative paths will be
                                   relative to each individual input file.
                                   Creates directories specified, but not
                                   recursively.  Also see --extended --help for
                                   advanced usage examples.
     --verbose            OPTIONAL Verbose mode/level.  (e.g. --verbose 2)
     --quiet              OPTIONAL Quiet mode.
     --overwrite          OPTIONAL Overwrite existing output files.  By
                                   default, existing output files will not be
                                   over-written.  See also --skip-existing.
     --skip-existing      OPTIONAL Skip existing output files.
     --force              OPTIONAL Prevent script-exit upon critical error and
                                   continue processing.  Supply twice to
                                   additionally prevent skipping the processing
                                   of input files that cause errors.  Use this
                                   option with extreme caution.  This option
                                   will not over-ride over-write protection.
                                   See also --overwrite or --skip-existing.
     --header,--noheader  OPTIONAL [On] Print commented script version, date,
                                   and command line call to each output file.
     --debug              OPTIONAL Debug mode/level.  (e.g. --debug --debug)
                                   Values less than 0 debug the template code
                                   that was used to create this script.
     --error-type-limit   OPTIONAL [5] Limits each type of error/warning to
                                   this number of outputs.  Intended to
                                   declutter output.  Note, a summary of
                                   warning/error types is printed when the
                                   script finishes, if one occurred or if in
                                   verbose mode.  0 = no limit.  See also
                                   --quiet.
     --dry-run            OPTIONAL Run without generating output files.
     --version            OPTIONAL Print version info.  Includes template
                                   version with --extended.
     --save-as-default    OPTIONAL Save the command line arguments.  Saved
                                   defaults are printed at the bottom of this
                                   usage output and used in every subsequent
                                   call of this script.  Supplying this flag
                                   replaces current defaults with all options
                                   that are provided with this flag.  Values
                                   are stored in [$defdir].
     --output-mode        OPTIONAL [error]{aggregate,split,error} When multiple
                                   input files output to the same output file,
                                   this option specifies what to do.  Aggregate
                                   mode will concatenate output in the common
                                   output file.  Split mode (valid only if this
                                   script accepts multiple types of input
                                   files) will create a unique output file name
                                   by appending a unique combination of input
                                   file names together (with a delimiting dot).
                                   Split mode will throw an error if a unique
                                   file name cannot be constructed (e.g. when 2
                                   input files of the same name in different
                                   directories are outputting to a common
                                   --outdir).  Error mode causes the script to
                                   quit with an error if multiple input files
                                   are detected to output to the same output
                                   file.
     --pipeline-mode      OPTIONAL [guess] Supply this flag to include the
                                   script name in errors, warnings, and debug
                                   messages.  If not supplied, the script will
                                   try to determine if it is running within a
                                   series of piped commands or as a part of a
                                   parent script.  Note, --debug will also do
                                   this, as well as prepend a call trace with
                                   line numbers.
     --extended           OPTIONAL Print extended usage/help/version/header.
                                   Supply alone for extended usage.  Includes
                                   extended version in output file headers.
                                   Incompatible with --noheader.  See --help &
                                   --version.
     --help               OPTIONAL Print general info and file format
                                   descriptions.  Includes advanced usage
                                   examples with --extended.
end_print
	  }

	my @user_defaults = getUserDefaults();
	print(scalar(@user_defaults) ?
	      "Current user defaults: [@user_defaults].\n" :
	      "No user defaults set.\n");
      }

    return(0);
  }
