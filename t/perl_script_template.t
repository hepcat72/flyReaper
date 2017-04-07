 # Run with `perl perl_script_template.t` or:
#          `perl perl_script_template.t ../perl_script_template`
#          `perl perl_script_template.t ../perl_script_template`
# in the t/ directory

use strict;
use warnings;
use lib '../lib';
use CommandLineInterface;

my($num_tests,$available_starts,$available_ranges,$changed_dir,$script);
BEGIN
  {
    $script = $0;

    $num_tests = `grep -E -c "^TEST[0-9]+:" $script`;
    chomp($num_tests);

    my $grepout = `grep -E "^TEST[0-9]+:|createTestScript" $script | grep -v "#" | grep -B 1 createTestScript | grep -E "^TEST[0-9]+:"`;
    my $astarts = [map {s/TEST(\d+):.*/$1/;$_} grep {/./} split(/\n/,$grepout,-1)];
    $available_starts = [1];
    push(@$available_starts,@$astarts);

    my(@ranges);
    my $range = [];
    for(@$available_starts) {
      if(scalar(@$range) == 0 ||
	 (scalar(@$range) && $_ - $range->[$#{$range}] == 1))
	{
	  push(@$range,$_);
	  next;
	}
      push(@ranges,$range);
      $range = [$_];
    }
    if(scalar(@$range))
      {push(@ranges,$range)}

    my @rangelist = (map {scalar(@$_) > 2 ? "$_->[0]-$_->[-1]" : @$_} @ranges);

    $available_ranges = [@rangelist];

    $changed_dir = 0;
    if($ENV{PWD} !~ m%/t/?$% && -e 't' && -d 't')
      {
	chdir('t');
	$changed_dir = 1;
	$ENV{PWD} .= '/t';
	$script =~ s%^t/%%;
      }

    debug("PWD: $ENV{PWD}\nScript: $script\n");
  }

my $test_script = './perl_script_template_test.pl';
my $source_script =
  (-e '../src/perl_script_template.pl' ?
   '../src/perl_script_template.pl' : $test_script);
my $sid = addInfileOption(GETOPTKEY   => 'i|template-script=s',
			  DEFAULT     => $source_script,
			  DETAIL_DESC => ('The template script to use in ' .
					  'creating test scripts.'));

my $test_version = '4.x';
addOption(GETOPTKEY   => 'v|test-version=s',
          GETOPTVAL   => \$test_version,
	  DEFAULT     => $test_version,
	  DETAIL_DESC => 'Use options specific to an older version.');

my $starting_test = 1;
addOption(GETOPTKEY => 't|starting-test=i',
          GETOPTVAL => \$starting_test,
	  REQUIRED  => 0,
	  ACCEPTS   => $available_ranges,
	  SMRY_DESC => 'Start with this test out of ' . $num_tests .
	  ' tests.  Not every test can be a starting test.  Use one of the ' .
	  'acceptable test numbers shown here.');

my $ending_test = $num_tests;
addOption(GETOPTKEY => 'e|ending-test=i',
          GETOPTVAL => \$ending_test,
	  REQUIRED  => 0,
	  SMRY_DESC => 'End with this test out of ' . $num_tests . ' tests.');

my $perl_call = 'perl -I../lib';
addOption(GETOPTKEY   => 'p|perl-call=s',
          GETOPTVAL   => \$perl_call,
	  DEFAULT     => $perl_call,
	  DETAIL_DESC => ('The perl call to put before each script.'));

my $script_debug = 0;
addOption(GETOPTKEY   => 'd|script-debug-mode:+',
          GETOPTVAL   => \$script_debug,
	  DEFAULT     => $script_debug,
	  DETAIL_DESC => ('Supply the --debug flag to the script calls.'));

setDefaults(HEADER     => 0,
	    DEFRUNMODE => 'run');

processCommandLine();

#Check labels for an error
my $cmd = "grep -E \"^TEST[0-9]+:\" $script | sort | uniq -c | grep -E \" [2-9]| [1-9][0-9]\"";
my $label_dupes = `$cmd`;
if(!-e $script)
  {error("Command for test label validation failed: [$cmd]",
	 ($! ne '' ? ": [$!]." : '.'))}
elsif($label_dupes =~ /./)
  {
    error("ERROR: Duplicate test labels exist in $script:\n$label_dupes");
    quit(2);
  }

if(scalar(grep {$_ == $starting_test} @$available_starts) == 0)
  {
    error("TEST [$starting_test] cannot be used as a starting test.");
    quit(1);
  }

if($starting_test)
  {$num_tests = $ending_test - $starting_test + 1}

my $debug_flag = '';
if($script_debug)
  {
    if($script_debug > 1)
      {$debug_flag = "--debug $script_debug"}
    else
      {$debug_flag = '--debug'}
  }

#Set the debug flag for debugging this test script
my $DEBUG = isDebug();

my $sizes = getFileGroupSizes($sid);
my $tmp_source_script = getInfile($sid);
if(scalar(@$sizes) > 1 || $sizes->[0] > 1)
  {warning("Only 1 source script is allowed.  Processing first one only: ",
	   "[$tmp_source_script].")}
if(defined($tmp_source_script) && -e $tmp_source_script)
  {$source_script = $tmp_source_script}

if(!defined($source_script))
  {die "Source script was not defined.\n"}

verbose({LEVEL => 2},"Initiating test of $source_script");

if(-e $source_script)
  {$test_script = createTestScript()}
if(!defined($test_script) || !-e $test_script)
  {die(join('',("Unable to parse script template [$source_script].  The ",
		"template may have been overwritten.  Please retrieve a ",
		"fresh copy from the repository.")))}

debug("Test Slug Script: [$test_script].");

die "Test Script: [$test_script] does not exist or is not executable."
  if(!-e $test_script || !-x $test_script);

if($test_version ne '2.17' && $test_version !~ /[34]\./)
  {die(join('',("A test scheme for version [$test_version] does not exist.  ",
		"I only have versions 2.17 and 3.x.  Your script should work ",
		"with version 3.x, as long as it is backwards compatible.  ",
		"You can use a later version script and run this test script ",
		"without supplying a version.")))}
elsif($test_version eq '2.17')
  {
    $starting_test = 1;
    $num_tests = 50;
  }

my $test_description  = '';
my $test_output       = '';
my $test_status       = 0;  #0 = Failed, !0 = Passed
my $test_cmd_append   = " --debug -1 2>&1";
my $test_cmd_opts     = '';
my $test_cmd          = '';
my $test_expected_str = q%%;
my $test_pattern      = '';
my $test_pipe_in      = '';
my $failures          = 0;
my $twooneseven       = 0;
my $test_num          = 0;
my $sub_test_num      = 0;
my $test_error        = '';
my $test_stdout       = '';
my $test_output1      = '';
my $test_output2      = '';
my $test_output3      = '';
my $test_output4      = '';
my $test_output5      = '';
my $test_output6      = '';
my $test_output7      = '';
my $test_output8      = '';
my $test_output9      = '';
my $test_should1      = '';
my $test_should2      = '';
my $test_warn_str     = '';
my $subtest_hash      = {};

#Set the number of tests at runtime instead of pre-compile because num_tests
#can change based on user options.
eval('use Test::More tests => $num_tests');

sub createTestScriptOld
  {
    open(SIN,$source_script) || die "Could not open [$source_script]. $!";
    my $script_content  = '';
    my $version         = '';
    my $doingslug1      = 0;
    my $gotvars         = 0;
    my $gotfileparams   = 0;
    my $gotfilesubmits  = 0;
    my $gotslug1        = 0;
    my $gotslug2        = 0;
    my $slug1done       = 0;
    my $gotname         = 0;
    my $script_name     = 'perl_script_template_';
    while(<SIN>)
      {
	if(/## DECLARE VARIABLES HERE/)
	  {
	    $gotvars         = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
my $files1 = [];
my $files2 = [];
end_edit
	  }
	elsif(/## ENTER YOUR COMMAND LINE PARAMETERS HERE AS BELOW/)
	  {
	    $gotfileparams   = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
   'j=s' => sub {push(@$files1,
                      [sglob($_[1])])},
   'k=s' => sub {push(@$files2,
                      [sglob($_[1])])},
end_edit
	  }
	elsif(/#ENTER INPUT FILE ARRAYS HERE/)
	  {
	    $gotfilesubmits  = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
                                     $files1,
                                     $files2,
end_edit
	  }
	elsif(!$slug1done && /my\s*\$line_num\s*=\s*0;/)
	  {
	    $doingslug1      = 1;
	    $slug1done       = 1;
	    $script_content .=<< 'end_edit';

    ##
    ## BEGIN TEST CODE 1
    ##


##TESTSLUG01



    ##
    ## END TEST CODE 1
    ##


end_edit
	  }
	elsif(/## ENTER YOUR POST-FILE-PROCESSING CODE HERE/)
	  {
	    $gotslug2        = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
##


##
## BEGIN TEST CODE 2
##


##TESTSLUG02


##
## END TEST CODE 2
end_edit
	  }
	elsif($doingslug1)
	  {
	    if(/^\s*\}/)
	      {
		$gotslug1   = 1;
		$doingslug1 = 0;
	      }
	  }
	else
	  {
	    $script_content .= $_;
	    if(/my\s*\$template_version\s*=\s*['"]?(\d[\d\.]+)/)
	      {
		my $vers      = $1;
		$vers         =~ s/\./_/g;
		$vers         =~ s/_(\d\Z|\d(?=_))/_0$1/g;
		$script_name .= $vers;
		$gotname      = 1;
	      }
	  }
      }
    close(SIN);

    if(!$gotname)
      {$script_name .= 'unk'}
    $script_name .= '_test.pl';

    if($gotvars && $gotfilesubmits && $gotfileparams && $gotslug1 && $gotslug2)
      {
	open(SOUT,">$script_name") ||
	  die "unable to write file [$script_name]. $!";
	print SOUT ($script_content);
	close(SOUT);
	chmod(0755,$script_name);
	return("./$script_name");
      }
    else
      {return(undef)}
  }

sub createTestScript
  {
    open(SIN,$source_script) || die "Could not open [$source_script]. $!";
    my $script_content  = '';
    my $script_name     = 'perl_script_template_';

    $script_content .=<< 'end_edit';
#!/usr/bin/perl -I../lib

##
## Template 1
##

use CommandLineInterface;

setScriptInfo(VERSION => '1.0',
              CREATED => '4/24/2016',
              AUTHOR  => 'Robert Leach',
              CONTACT => 'rleach@princeton.edu',
              COMPANY => 'Princeton University',
              LICENSE => 'Copyright 2016',
              HELP    => 'Test template script 1 with 2 code slugs.');

my $filetype1 = addInfileOption();
my $filetype2 = addInfileOption('j=s');
my $filetype3 = addInfileOption('k=s');

while(nextFileCombo())
  {



    ##
    ## BEGIN TEST CODE 1
    ##


##TESTSLUG01



    ##
    ## END TEST CODE 1
    ##



  }



##
## BEGIN TEST CODE 2
##


##TESTSLUG02


##
## END TEST CODE 2
##



end_edit

    my $vers      = $CommandLineInterface::VERSION;
    $vers         =~ s/\./_/g;
    $vers         =~ s/_(\d\Z|\d(?=_))/_0$1/g;
    $script_name .= $vers;

    $script_name .= '_test.pl';

    open(SOUT,">$script_name") ||
      die "unable to write file [$script_name]. $!";
    print SOUT ($script_content);
    close(SOUT);
    chmod(0755,$script_name);
    return("./$script_name");
  }

#Removes the loop and adds 3 extra file types (-j -k -l) and an extra outfile suffix (-p)
sub createTestScript2Old
  {
    open(SIN,$source_script) || die "Could not open [$source_script]. $!";
    my $script_content  = '';
    my $version         = '';
    my $doingslug1      = 0;
    my $gotpreproc      = 0;
    my $gotvars         = 0;
    my $gotfileparams   = 0;
    my $gotfilesubmits  = 0;
    my $gotfilesuffixes = 0;
    my $gotslug1        = 0;
    my $gotslug2        = 0;
    my $slug1done       = 0;
    my $gotname         = 0;
    my $skip_section    = 0;
    my $script_name     = 'perl_script_template_';
    while(<SIN>)
      {
	if(/## DECLARE VARIABLES HERE/)
	  {
	    $gotvars         = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
my $files1 = [];
my $files2 = [];
my $files3 = [];
my($f1suff);
end_edit
	  }
	elsif(/## ENTER YOUR COMMAND LINE PARAMETERS HERE AS BELOW/)
	  {
	    $gotfileparams   = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
   'j=s' => sub {push(@$files1,
                      [sglob($_[1])])},
   'k=s' => sub {push(@$files2,
                      [sglob($_[1])])},
   'l=s' => sub {push(@$files3,
                      [sglob($_[1])])},
   'p|f1-suffix=s' => \$f1suff,
end_edit
	  }
	elsif(/#ENTER INPUT FILE ARRAYS HERE/)
	  {
	    $gotfilesubmits  = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
                                     $files1,
                                     $files2,
                                     $files3,
end_edit
	  }
	elsif(/#ENTER SUFFIX ARRAYS HERE IN SAME ORDER/)
	  {
	    $gotfilesuffixes  = 1;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
                                     [$f1suff],
end_edit
	  }
	elsif(!$slug1done && /my\s*\$line_num\s*=\s*0;/)
	  {
	    $doingslug1      = 1;
	    $slug1done       = 1;
	    $script_content .=<< 'end_edit';

    ##
    ## BEGIN TEST CODE 1
    ##


##TESTSLUG01



    ##
    ## END TEST CODE 1
    ##


end_edit
	  }
	elsif(/## ENTER YOUR PRE-FILE-PROCESSING CODE HERE/)
	  {
	    $gotpreproc = 1;
	    $skip_section = 1;
	    $script_content .= $_;
	  }
	elsif(/## ENTER YOUR POST-FILE-PROCESSING CODE HERE/)
	  {
	    $gotslug2        = 1;
	    $skip_section    = 0;
	    $script_content .= $_;
	    $script_content .=<< 'end_edit';
##


##
## BEGIN TEST CODE 2
##


##TESTSLUG02


##
## END TEST CODE 2
end_edit
	  }
	elsif($doingslug1)
	  {
	    if(/^\s*\}/)
	      {
		$gotslug1   = 1;
		$doingslug1 = 0;
	      }
	  }
	elsif(!$skip_section)
	  {
	    $script_content .= $_;
	    if(/my\s*\$template_version\s*=\s*['"]?(\d[\d\.]+)/)
	      {
		my $vers      = $1;
		$vers         =~ s/\./_/g;
		$vers         =~ s/_(\d\Z|\d(?=_))/_0$1/g;
		$script_name .= $vers;
		$gotname      = 1;
	      }
	  }
      }
    close(SIN);

    if(!$gotname)
      {$script_name .= 'unk'}
    $script_name .= '_test.pl';

    if($gotvars && $gotfilesubmits && $gotfileparams && $gotslug1 &&
       $gotslug2 && $gotfilesuffixes && $gotpreproc)
      {
	open(SOUT,">$script_name") ||
	  die "unable to write file [$script_name]. $!";
	print SOUT ($script_content);
	close(SOUT);
	chmod(0755,$script_name);
	return("./$script_name");
      }
    else
      {return(undef)}
  }

#Removes the loop and adds 3 extra file types (-j -k -l) and an extra outfile suffix (-p)
sub createTestScript2
  {
    open(SIN,$source_script) || die "Could not open [$source_script]. $!";
    my $script_content  = '';
    my $script_name     = 'perl_script_template_';

    $script_content .=<< 'end_edit';
#!/usr/bin/perl -I../lib

##
## Template 2
##

use CommandLineInterface;

setScriptInfo(VERSION => '1.0',
              CREATED => '4/24/2016',
              AUTHOR  => 'Robert Leach',
              CONTACT => 'rleach@princeton.edu',
              COMPANY => 'Princeton University',
              LICENSE => 'Copyright 2016',
              HELP    => 'Test template script 1 with 2 code slugs.');

my $filetype1 = addInfileOption();
my $sufftype1 = addOutfileSuffixOption();

my $filetype2 = addInfileOption('j=s');
my $filetype3 = addInfileOption('k=s');
my $filetype4 = addInfileOption('l=s');
my $sufftype2 = addOutfileSuffixOption('p|f1-suffix',$filetype2);

    ##
    ## BEGIN TEST CODE 1
    ##


##TESTSLUG01



    ##
    ## END TEST CODE 1
    ##





##
## BEGIN TEST CODE 2
##


##TESTSLUG02


##
## END TEST CODE 2
##



end_edit

    my $vers      = $CommandLineInterface::VERSION;
    $vers         =~ s/\./_/g;
    $vers         =~ s/_(\d\Z|\d(?=_))/_0$1/g;
    $script_name .= $vers;

    $script_name .= '_test.pl';

    open(SOUT,">$script_name") ||
      die "unable to write file [$script_name]. $!";
    print SOUT ($script_content);
    close(SOUT);
    chmod(0755,$script_name);
    return("./$script_name");
  }


sub createTestScript3
  {
    open(SIN,$source_script) || die "Could not open [$source_script]. $!";
    my $script_content  = '';
    my $script_name     = 'perl_script_template_';

    $script_content .=<< 'end_edit';
#!/usr/bin/perl -I../lib

##
## Template 2
##

use CommandLineInterface;

setScriptInfo(VERSION => '1.0',
              CREATED => '4/24/2016',
              AUTHOR  => 'Robert Leach',
              CONTACT => 'rleach@princeton.edu',
              COMPANY => 'Princeton University',
              LICENSE => 'Copyright 2016',
              HELP    => 'Test template script 1 with 1 code slug.');

##
## BEGIN TEST CODE 1
##


##TESTSLUG01



##
## END TEST CODE 1
##



end_edit

    my $vers      = $CommandLineInterface::VERSION;
    $vers         =~ s/\./_/g;
    $vers         =~ s/_(\d\Z|\d(?=_))/_0$1/g;
    $script_name .= $vers;

    $script_name .= '_test.pl';

    open(SOUT,">$script_name") ||
      die "unable to write file [$script_name]. $!";
    print SOUT ($script_content);
    close(SOUT);
    chmod(0755,$script_name);
    return("./$script_name");
  }


sub createTestScript4
  {
    open(SIN,$source_script) || die "Could not open [$source_script]. $!";
    my $script_content  = '';
    my $script_name     = 'perl_script_template_';

    $script_content .=<< 'end_edit';
#!/usr/bin/perl -I../lib

##
## Template 2
##

use warnings;
use strict;
use CommandLineInterface;

setScriptInfo(VERSION => '1.0',
              CREATED => '4/24/2016',
              AUTHOR  => 'Robert Leach',
              CONTACT => 'rleach@princeton.edu',
              COMPANY => 'Princeton University',
              LICENSE => 'Copyright 2016',
              HELP    => 'Test template script 1 with strict & 1 code slug.');

##
## BEGIN TEST CODE 1
##


##TESTSLUG01



##
## END TEST CODE 1
##



end_edit

    my $vers      = $CommandLineInterface::VERSION;
    $vers         =~ s/\./_/g;
    $vers         =~ s/_(\d\Z|\d(?=_))/_0$1/g;
    $script_name .= $vers;

    $script_name .= '_test.pl';

    open(SOUT,">$script_name") ||
      die "unable to write file [$script_name]. $!";
    print SOUT ($script_content);
    close(SOUT);
    chmod(0755,$script_name);
    return("./$script_name");
  }


sub debug1
  {
    return() if($test_status || !$DEBUG);
    print("TEST$test_num: $test_cmd\n",
	  "\tExpected: [$test_expected_str]\n",
	  "\tGot:      [$test_output]\n");
  }

sub debug2
  {
    return() if($test_status || !$DEBUG);
    print("TEST$test_num: $test_cmd\n",
          "\tExpected STDOUT: [$test_stdout]\n",
          "\tGot:             [$test_output]\n",
          "\tExpected File1:  [$test_should1]\n",
          "\tGot:             [$test_output1]\n",
          "\tExpected File2:  [$test_should2]\n",
          "\tGot:             [$test_output2]\n",
          "\tExpected STDERR: [$test_warn_str]\n",
          "\tGot:             [$test_error]\n",
	 );
  }

#Globals used: $test_num, $test_cmd
sub debug3
  {
    my $expected_array = $_[0]; #[[output_name,string_describing_expectation],]
    my $got_array      = $_[1]; #[[output_name,actual_output],...]
    #Tests 127+ expect this input:
    my $test_status    = (defined($_[2]) ? $_[2] : $test_status);
    my $test_cmd       = (defined($_[3]) ? $_[3] : $test_cmd);
    if(scalar(@$expected_array) != scalar(@$got_array) ||
       scalar(grep {ref($_) ne 'ARRAY' || scalar(@$_) != 2} @$expected_array)||
       scalar(grep {ref($_) ne 'ARRAY' || scalar(@$_) != 2} @$got_array))
      {
	print STDERR "debug3: Bad parameters.";
	return();
      }
    #return() if($test_status || !$DEBUG);
    print("TEST$test_num: $test_cmd\n");
    for(my $i = 0;$i < scalar(@$got_array);$i++)
      {
	$expected_array->[$i]->[1] =~ s/\n(?=.)/\n\t                  /g;
	$expected_array->[$i]->[1] =~ s/\n$/\n\t                 /g;
	$got_array->[$i]->[1]      =~ s/\n(?=.)/\n\t                  /g;
	$got_array->[$i]->[1]      =~ s/\n$/\n\t                 /g;
	print("\tExpected $expected_array->[$i]->[0]: ",
	      "[$expected_array->[$i]->[1]]\n",
	      "\tGot:             [$got_array->[$i]->[1]]\n");
      }
  }

#Takes a string of code and a pattern and finds the pattern in the inscript and
#creates an outscript that has the replaced code
sub insertTemplateCode
  {
    my $code      = $_[0];
    my $pattern   = $_[1];
    my $inscript  = $_[2];
    my $outscript = $_[3];

    unless(open(INS,$inscript))
      {
        print STDERR ("Unable to open [$inscript]. $!\n");
        return(0);
      }
    my $content = join('',<INS>);
    unless($content =~ s/$pattern/$code/si)
      {
        print STDERR ("ERROR: Could not insert code in input script ",
                      "[$inscript] using pattern [$pattern].\n");
        return(0);
      }
    close(INS);

    unless(open(OUTS,">$outscript"))
      {
        print STDERR ("Unable to open [$outscript]. $!\n");
        return(0);
      }
    print OUTS ($content);
    close(OUTS);
    chmod(0755,$outscript);

    return(1);
  }









##
## These variables previously had been declared and iniialized for specific
## sets of tests below, but if I'm going to allow users to skip tests by
## setting a starting_test number, I need to move those declarations/
## initializations above the goto statement, so I'm placing them here until I
## have revamped this test script.  Some of the initial value are thus weird in
## the current pre-testing context and reflect the values that they got for the
## first test in which they were used.
##

my $pattern          = '##TESTSLUG02';
my $in_script        = $test_script;
my $testfnum         = 1;
my $testf            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf`;
$testfnum++;
my $testf2            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf2`;
$testfnum++;
my $testf3            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf3`;
$testfnum++;
my $testf4            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf4`;
$testfnum++;
my $testf5            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf5`;
$testfnum++;
my $testf6            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf6`;
$testfnum++;
my $testf7            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf7`;
$testfnum++;
my $testf8            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf8`;
$testfnum++;
my $testf9            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf9`;
my $out_script       = "$in_script.test$test_num.req34_$sub_test_num.pl";
my $code             = '';
my $outf1            = '';
my $outf2            = '';
my $outf3            = '';
my $outf4            = '';
my $outf5            = '';
my $outf6            = '';
my $outf7            = '';
my $outf8            = '';
my $outf9            = '';
my $test_errorf      = '';
my $test_warn_pat    = quotemeta($test_warn_str);
my $test_desc_def    = "Req34. Select automatically";
my $no_clean         = 1;
my $userpat          = quotemeta("#User: $ENV{USER}");
my $timepat          = quotemeta("#Time: ") . '\S+';
my $hostpat          = quotemeta("#Host: $ENV{HOST}");
my $dirpat           = quotemeta("#Directory: $ENV{PWD}");
my $err_verbose1_pat = quotemeta($testf2);
my $err_verbose2_pat = quotemeta("[$testf2] Input file done.");
my $test_outf1 = '';
my $test_outf2 = '';
my $test_outf3 = '';
my $test_outf4 = '';
my $test_outf5 = '';
my $test_outf6 = '';
my $test_outf7 = '';
my $test_outf8 = '';
my $test_outf9 = '';
my $should_outf1_str    = "1\n1\n";
my $should_outf2_str    = "";
my $should_outf3_str    = "";
my $should_outf4_str    = "";
my $should_outf5_str    = "";
my $should_outf6_str    = "";
my $should_outf7_str    = "";
my $should_outf8_str    = "";
my $should_outf9_str    = "";
my $should_stdout_str   = "";
my $should_stderr_str   = "";
my $should_outf1_pat    = '';
my $should_outf2_pat    = '';
my $should_outf3_pat    = '';
my $should_outf4_pat    = '';
my $should_outf5_pat    = '';
my $should_outf6_pat    = '';
my $should_outf7_pat    = '';
my $should_outf8_pat    = '';
my $should_outf9_pat    = '';
my $should_stdout_pat   = '';
my $should_stderr_pat   = '';
my $shouldnt_outf1_pat  = '';
my $shouldnt_outf2_pat  = '';
my $shouldnt_outf3_pat  = '';
my $shouldnt_outf4_pat  = '';
my $shouldnt_outf5_pat  = '';
my $shouldnt_outf6_pat  = '';
my $shouldnt_outf7_pat  = '';
my $shouldnt_outf8_pat  = '';
my $shouldnt_outf9_pat  = '';
my $shouldnt_stdout_pat = '';
my $shouldnt_stderr_pat = 'ERROR';
my $splitf1       = $testf;
my $splitf2       = $testf2;
my $splitf3       = $testf3;
my $splitf4       = $testf4;
my $splitf5       = $testf5;
my $splitf6       = $testf6;
my $splitf7       = $testf7;
my($exit_code);
my $testdnum = 1;
my $testd1 = "$test_script.test_outdir$testdnum.dir";
my $outd1  = "$testd1.out";
my($inodenum,$newinodenum);
my $testd2 = "$test_script.test_outdir$testdnum.dir";
my $outd2  = "$testd2.out";
my($inodenum2,$newinodenum2,$inodenum3,$newinodenum3,$inodenum4,$newinodenum4);
my $reqnum = 126;
my $testdefdir = 'TESTUSERDEFAULTS';

END
  {
    #This is a temporary clean-up added specifically for the flyReaper installation
    if(-e 'perl_script_template_4_052_test.pl')
      {`rm -rf *.txt *.out *.test TEST* *.pl.* *~ perl_script_template_4_052_test.pl`}
    if($changed_dir)
      {
	chdir('..');
	$script = "t/$script";
	$changed_dir = 1;
      }
  }

#Basic test that handles up to 6 input files
sub test6f
  {
    #Describe the test
    my $test_num         = $_[0];
    my $sub_test_num     = $_[1];
    my $description      = $_[2];
    my $reqnum           = $_[44]; #Fix this later, should be index 3
    my $test_description = "TEST$test_num: REQ$reqnum SubTest$sub_test_num " .
      "- $description";

    #Name the files involved
    my $in_script        = $_[3];
    my $out_script       = "$in_script.test$test_num.$sub_test_num.pl";
    my $test_errorf      = "$out_script.err.txt";
    my $testf            = $_[4];       #The input files (supplied on cmd line)
    my $testf2           = $_[5];
    my $testf3           = $_[6];
    my $testf4           = $_[7];
    my $testf5           = $_[8];
    my $testf6           = $_[9];
    my $outf1            = $_[10];      #The output files you expect to get
    $outf1               =~ s%/\./%/%g if(defined($outf1));
    my $outf2            = $_[11];
    $outf2               =~ s%/\./%/%g if(defined($outf2));
    my $outf3            = $_[12];
    $outf3               =~ s%/\./%/%g if(defined($outf3));
    my $outf4            = $_[13];
    $outf4               =~ s%/\./%/%g if(defined($outf4));
    my $outf5            = $_[14];
    $outf5               =~ s%/\./%/%g if(defined($outf5));
    my $outf6            = $_[15];
    $outf6               =~ s%/\./%/%g if(defined($outf6));
    #global $testf file (contains the string "test\n")

    #Prepare the variables that will hold the output
    my $test_error = '';
    my $test_outf1 = '';
    my $test_outf2 = '';
    my $test_outf3 = '';
    my $test_outf4 = '';
    my $test_outf5 = '';
    my $test_outf6 = '';

    #Clean up any previous tests
    unlink($outf1)  if(defined($outf1) && $outf1 ne '' && -e $outf1);
    unlink($outf2)  if(defined($outf2) && $outf2 ne '' && -e $outf2);
    unlink($outf3)  if(defined($outf3) && $outf3 ne '' && -e $outf3);
    unlink($outf4)  if(defined($outf4) && $outf4 ne '' && -e $outf4);
    unlink($outf5)  if(defined($outf5) && $outf5 ne '' && -e $outf5);
    unlink($outf6)  if(defined($outf6) && $outf6 ne '' && -e $outf6);
    #`rm -rf $outd1` if($outd1 ne '' && -e $outd1);
    #`rm -rf $outd2` if($outd2 ne '' && -e $outd2);

    #Create/edit the script to add the test code
    my $code    = $_[16];
    my $pattern = $_[17];
    insertTemplateCode($code,$pattern,$in_script,$out_script);

    #Create the command
    my $test_cmd_opts = $_[18];
    $test_cmd_opts   .= " $debug_flag" unless($test_cmd_opts =~ /--debug/);
    my $test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

    #Run the command
    my $test_output   = `$test_cmd`;

    my $exit_code = $?;

    $test_error = '';
    if(-e $test_errorf && open(INERR,$test_errorf))
      {
	$test_error = join('',<INERR>);
	close(INERR);
      }

    $test_outf1 = '';
    if(defined($outf1) && -e $outf1 && open(IN,$outf1))
      {
	$test_outf1 = join('',<IN>);
	close(IN);
      }

    $test_outf2 = '';
    if(defined($outf2) && -e $outf2 && open(IN,$outf2))
      {
	$test_outf2 = join('',<IN>);
	close(IN);
      }

    $test_outf3 = '';
    if(defined($outf3) && -e $outf3 && open(IN,$outf3))
      {
	$test_outf3 = join('',<IN>);
	close(IN);
      }

    $test_outf4 = '';
    if(defined($outf4) && -e $outf4 && open(IN,$outf4))
      {
	$test_outf4 = join('',<IN>);
	close(IN);
      }

    $test_outf5 = '';
    if(defined($outf5) && -e $outf5 && open(IN,$outf5))
      {
	$test_outf5 = join('',<IN>);
	close(IN);
      }

    $test_outf6 = '';
    if(defined($outf6) && -e $outf6 && open(IN,$outf6))
      {
	$test_outf6 = join('',<IN>);
	close(IN);
      }


    #Create a string or pattern for the expected result
    my $should_stdout_str   = $_[19];
    my $should_stderr_str   = $_[20];
    my $should_outf1_str    = $_[21];
    my $should_outf2_str    = $_[22];
    my $should_outf3_str    = $_[23];
    my $should_outf4_str    = $_[24];
    my $should_outf5_str    = $_[25];
    my $should_outf6_str    = $_[26];

    my $should_stdout_pat   = $_[27];
    my $should_stderr_pat   = $_[28];
    my $should_outf1_pat    = $_[29];
    my $should_outf2_pat    = $_[30];
    my $should_outf3_pat    = $_[31];
    my $should_outf4_pat    = $_[32];
    my $should_outf5_pat    = $_[33];
    my $should_outf6_pat    = $_[34];

    my $shouldnt_stdout_pat = $_[35];
    my $shouldnt_stderr_pat = $_[36];
    my $shouldnt_outf1_pat  = $_[37];
    my $shouldnt_outf2_pat  = $_[38];
    my $shouldnt_outf3_pat  = $_[39];
    my $shouldnt_outf4_pat  = $_[40];
    my $shouldnt_outf5_pat  = $_[41];
    my $shouldnt_outf6_pat  = $_[42];

    my $exit_error          = $_[43]; #Non-zero if expected to return an exit
                                      #code not equal to 0

    #Evaluate the result
    my $test_status = ((!defined($should_outf1_str) ||
			(-e $outf1 && $should_outf1_str eq $test_outf1)) &&
		       (!defined($should_outf2_str) ||
			(-e $outf2 && $should_outf2_str eq $test_outf2)) &&
		       (!defined($should_outf3_str) ||
			(-e $outf3 && $should_outf3_str eq $test_outf3)) &&
		       (!defined($should_outf4_str) ||
			(-e $outf4 && $should_outf4_str eq $test_outf4)) &&
		       (!defined($should_outf5_str) ||
			(-e $outf5 && $should_outf5_str eq $test_outf5)) &&
		       (!defined($should_outf6_str) ||
			(-e $outf6 && $should_outf6_str eq $test_outf6)) &&

		       (!defined($should_stdout_str) ||
			$should_stdout_str eq $test_output) &&
		       (!defined($should_stderr_str) ||
			$should_stderr_str eq $test_error) &&

		       (!defined($should_outf1_pat) ||
			(-e $outf1 && $test_outf1 =~ /$should_outf1_pat/)) &&
		       (!defined($should_outf2_pat) ||
			(-e $outf2 && $test_outf2 =~ /$should_outf2_pat/)) &&
		       (!defined($should_outf3_pat) ||
			(-e $outf3 && $test_outf3 =~ /$should_outf3_pat/)) &&
		       (!defined($should_outf4_pat) ||
			(-e $outf4 && $test_outf4 =~ /$should_outf4_pat/)) &&
		       (!defined($should_outf5_pat) ||
			(-e $outf5 && $test_outf5 =~ /$should_outf5_pat/)) &&
		       (!defined($should_outf6_pat) ||
			(-e $outf6 && $test_outf6 =~ /$should_outf6_pat/)) &&

		       (!defined($shouldnt_outf1_pat) ||
			(-e $outf1 && $test_outf1 !~ /$shouldnt_outf1_pat/)) &&
		       (!defined($shouldnt_outf2_pat) ||
			(-e $outf2 && $test_outf2 !~ /$shouldnt_outf2_pat/)) &&
		       (!defined($shouldnt_outf3_pat) ||
			(-e $outf3 && $test_outf3 !~ /$shouldnt_outf3_pat/)) &&
		       (!defined($shouldnt_outf4_pat) ||
			(-e $outf4 && $test_outf4 !~ /$shouldnt_outf4_pat/)) &&
		       (!defined($shouldnt_outf5_pat) ||
			(-e $outf5 && $test_outf5 !~ /$shouldnt_outf5_pat/)) &&
		       (!defined($shouldnt_outf6_pat) ||
			(-e $outf6 && $test_outf6 !~ /$shouldnt_outf6_pat/)) &&

		       (!defined($should_stdout_pat) ||
			$test_output =~ /$should_stdout_pat/) &&
		       (!defined($shouldnt_stdout_pat) ||
			$test_output !~ /$shouldnt_stdout_pat/) &&

		       (!defined($should_stderr_pat) ||
			$test_error =~ /$should_stderr_pat/) &&
		       (!defined($shouldnt_stderr_pat) ||
			$test_error !~ /$shouldnt_stderr_pat/) &&

		       (($exit_error == 0 && $exit_code == 0) ||
			($exit_error != 0 && $exit_code != 0)));
    ok($test_status,$test_description);

    #If the test failed while in debug mode, print a description of what went
    #wrong
    if(!$test_status && $DEBUG)
      {
	my $success = (($exit_error != 0  && $exit_code != 0) ||
		       ($exit_error == 0  && $exit_code == 0));
	my $expected = ($success ? [] : [['EXITCO',$exit_error]]);
	my $gotarray = ($success ? [] : [['EXITCO',$exit_code]]);
	foreach my $ary (['STDOUT','STDOUT',$test_output,$should_stdout_str,
			  $should_stdout_pat,$shouldnt_stdout_pat],
			 ['STDERR','STDERR',$test_error,$should_stderr_str,
			  $should_stderr_pat,$shouldnt_stderr_pat],
			 ['OUTF1 ',$outf1,$test_outf1,$should_outf1_str,
			  $should_outf1_pat,$shouldnt_outf1_pat],
			 ['OUTF2 ',$outf2,$test_outf2,$should_outf2_str,
			  $should_outf2_pat,$shouldnt_outf2_pat],
			 ['OUTF3 ',$outf3,$test_outf3,$should_outf3_str,
			  $should_outf3_pat,$shouldnt_outf3_pat],
			 ['OUTF4 ',$outf4,$test_outf4,$should_outf4_str,
			  $should_outf4_pat,$shouldnt_outf4_pat],
			 ['OUTF5 ',$outf5,$test_outf5,$should_outf5_str,
			  $should_outf5_pat,$shouldnt_outf5_pat],
			 ['OUTF6 ',$outf6,$test_outf6,$should_outf6_str,
			  $should_outf6_pat,$shouldnt_outf6_pat])
	  {
	    if(defined($ary->[3]))
	      {
		if((($ary->[1] eq 'STDOUT' || $ary->[1] eq 'STDERR' ||
		     -e $ary->[1]) && $ary->[2] ne $ary->[3]) ||
		   ($ary->[1] ne 'STDOUT' && $ary->[1] ne 'STDERR' &&
		    !-e $ary->[1]))
		  {
		    push(@$expected,[$ary->[0],$ary->[3]]);
		    push(@$gotarray,[$ary->[0],$ary->[2]]);
		  }
	      }
	    if(defined($ary->[4]))
	      {
		if((($ary->[1] eq 'STDOUT' || $ary->[1] eq 'STDERR' ||
		     -e $ary->[1]) && $ary->[2] !~ /$ary->[4]/) ||
		   ($ary->[1] ne 'STDOUT' && $ary->[1] ne 'STDERR' &&
		    !-e $ary->[1]))
		  {
		    push(@$expected,[$ary->[0],"/$ary->[4]/"]);
		    push(@$gotarray,[$ary->[0],$ary->[2]]);
		  }
	      }
	    if(defined($ary->[5]))
	      {
		if((($ary->[1] eq 'STDOUT' || $ary->[1] eq 'STDERR' ||
		     -e $ary->[1]) && $ary->[2] =~ /$ary->[5]/) ||
		   ($ary->[1] ne 'STDOUT' && $ary->[1] ne 'STDERR' &&
		    !-e $ary->[1]))
		  {
		    push(@$expected,[$ary->[0],"!~ /$ary->[5]/"]);
		    push(@$gotarray,[$ary->[0],$ary->[2]]);
		  }
	      }
	  }

	debug3($expected,$gotarray,$test_status,$test_cmd);
      }

    #Clean up
    unless($no_clean)
      {
	#Clean up files:
	foreach my $tfile (grep {defined($_)} ($outf1,$outf2,$outf3,$outf4,
					       $outf5,$outf6,$test_errorf,
					       $out_script))
	  {
	    verbose("Cleaning $tfile");
	    unlink($tfile);
	  }
	#foreach my $tdir ($outd1,$outd2)
	#  {`rm -rf $tdir` if(defined($tdir) && $tdir ne '' && -e $tdir)}
      }
  }

#Basic test that handles up to 6 input files.  Adds the ability to ensure some
#outfiles WERE NOT created
sub test6f2
  {
    #Describe the test
    my $test_num         = $_[0];
    my $sub_test_num     = $_[1];
    my $description      = $_[2];
    my $reqnum           = $_[50]; #Fix this later, should be index 3
    my $test_description = "TEST$test_num: REQ$reqnum SubTest$sub_test_num " .
      "- $description";

    if(exists($subtest_hash->{$reqnum}) &&
       exists($subtest_hash->{$reqnum}->{$sub_test_num}))
      {warning("Requirement: [$reqnum] has duplicate subtest numbers: ",
	       "[$sub_test_num] for test [$test_num].")}
    $subtest_hash->{$reqnum}->{$sub_test_num} = 1;

    #Name the files involved
    my $in_script        = $_[3];
    my $out_script       = "$in_script.test$test_num.$sub_test_num.pl";
    my $test_errorf      = "$out_script.err.txt";
    my $testf            = $_[4];       #The input files (supplied on cmd line)
    my $testf2           = $_[5];
    my $testf3           = $_[6];
    my $testf4           = $_[7];
    my $testf5           = $_[8];
    my $testf6           = $_[9];
    my $outf1            = $_[10];      #The output files you expect to get
    $outf1               =~ s%/\./%/%g if(defined($outf1));
    my $outf2            = $_[11];
    $outf2               =~ s%/\./%/%g if(defined($outf2));
    my $outf3            = $_[12];
    $outf3               =~ s%/\./%/%g if(defined($outf3));
    my $outf4            = $_[13];
    $outf4               =~ s%/\./%/%g if(defined($outf4));
    my $outf5            = $_[14];
    $outf5               =~ s%/\./%/%g if(defined($outf5));
    my $outf6            = $_[15];
    $outf6               =~ s%/\./%/%g if(defined($outf6));
    #global $testf file (contains the string "test\n")

    #Prepare the variables that will hold the output
    my $test_error = '';
    my $test_outf1 = '';
    my $test_outf2 = '';
    my $test_outf3 = '';
    my $test_outf4 = '';
    my $test_outf5 = '';
    my $test_outf6 = '';

    #Added a param to not delete a pre-existing file to test the output modes
    my $nodel1 = $_[51];

    #Clean up any previous tests
    unlink($outf1)  if(defined($outf1) && $outf1 ne '' && -e $outf1 &&
		       (!defined($nodel1) || !$nodel1));
    unlink($outf2)  if(defined($outf2) && $outf2 ne '' && -e $outf2);
    unlink($outf3)  if(defined($outf3) && $outf3 ne '' && -e $outf3);
    unlink($outf4)  if(defined($outf4) && $outf4 ne '' && -e $outf4);
    unlink($outf5)  if(defined($outf5) && $outf5 ne '' && -e $outf5);
    unlink($outf6)  if(defined($outf6) && $outf6 ne '' && -e $outf6);
    #`rm -rf $outd1` if($outd1 ne '' && -e $outd1);
    #`rm -rf $outd2` if($outd2 ne '' && -e $outd2);

    #Create/edit the script to add the test code
    my $code    = $_[16];
    my $pattern = $_[17];
    insertTemplateCode($code,$pattern,$in_script,$out_script);

    #Create the command
    my $first_on_stdin = defined($_[52]) ? $_[52] : 0;
    my $test_cmd_opts = $_[18];
    $test_cmd_opts   .= " $debug_flag" unless($test_cmd_opts =~ /--debug/);
    my $test_cmd      = $first_on_stdin ? "cat $testf | " : '';
    $test_cmd        .= "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

    #Run the command
    verbose({LEVEL => 2},"TEST$test_num: $test_cmd");
    my $test_output   = `$test_cmd`;

    my $exit_code = $?;

    $test_error = '';
    if(-e $test_errorf && open(INERR,$test_errorf))
      {
	$test_error = join('',<INERR>);
	close(INERR);
      }

    $test_outf1 = '';
    if(defined($outf1) && -e $outf1 && open(IN,$outf1))
      {
	$test_outf1 = join('',<IN>);
	close(IN);
      }

    $test_outf2 = '';
    if(defined($outf2) && -e $outf2 && open(IN,$outf2))
      {
	$test_outf2 = join('',<IN>);
	close(IN);
      }

    $test_outf3 = '';
    if(defined($outf3) && -e $outf3 && open(IN,$outf3))
      {
	$test_outf3 = join('',<IN>);
	close(IN);
      }

    $test_outf4 = '';
    if(defined($outf4) && -e $outf4 && open(IN,$outf4))
      {
	$test_outf4 = join('',<IN>);
	close(IN);
      }

    $test_outf5 = '';
    if(defined($outf5) && -e $outf5 && open(IN,$outf5))
      {
	$test_outf5 = join('',<IN>);
	close(IN);
      }

    $test_outf6 = '';
    if(defined($outf6) && -e $outf6 && open(IN,$outf6))
      {
	$test_outf6 = join('',<IN>);
	close(IN);
      }


    #Files to make sure NOT created
    my $no_outf1 = $_[19];
    my $no_outf2 = $_[20];
    my $no_outf3 = $_[21];
    my $no_outf4 = $_[22];
    my $no_outf5 = $_[23];
    my $no_outf6 = $_[24];


    #Create a string or pattern for the expected result
    my $should_stdout_str   = $_[25];
    my $should_stderr_str   = $_[26];
    my $should_outf1_str    = $_[27];
    my $should_outf2_str    = $_[28];
    my $should_outf3_str    = $_[29];
    my $should_outf4_str    = $_[30];
    my $should_outf5_str    = $_[31];
    my $should_outf6_str    = $_[32];

    my $should_stdout_pat   = $_[33];
    my $should_stderr_pat   = $_[34];
    my $should_outf1_pat    = $_[35];
    my $should_outf2_pat    = $_[36];
    my $should_outf3_pat    = $_[37];
    my $should_outf4_pat    = $_[38];
    my $should_outf5_pat    = $_[39];
    my $should_outf6_pat    = $_[40];

    my $shouldnt_stdout_pat = $_[41];
    my $shouldnt_stderr_pat = $_[42];
    my $shouldnt_outf1_pat  = $_[43];
    my $shouldnt_outf2_pat  = $_[44];
    my $shouldnt_outf3_pat  = $_[45];
    my $shouldnt_outf4_pat  = $_[46];
    my $shouldnt_outf5_pat  = $_[47];
    my $shouldnt_outf6_pat  = $_[48];

    my $exit_error          = $_[49]; #Non-zero if expected to return an exit
                                      #code not equal to 0

    #Evaluate the result
    my $test_status = ((!defined($should_outf1_str) ||
			(-e $outf1 && $should_outf1_str eq $test_outf1)) &&
		       (!defined($should_outf2_str) ||
			(-e $outf2 && $should_outf2_str eq $test_outf2)) &&
		       (!defined($should_outf3_str) ||
			(-e $outf3 && $should_outf3_str eq $test_outf3)) &&
		       (!defined($should_outf4_str) ||
			(-e $outf4 && $should_outf4_str eq $test_outf4)) &&
		       (!defined($should_outf5_str) ||
			(-e $outf5 && $should_outf5_str eq $test_outf5)) &&
		       (!defined($should_outf6_str) ||
			(-e $outf6 && $should_outf6_str eq $test_outf6)) &&

		       #Test that these files that are not supposed to be
		       #created did not get created
		       (!defined($no_outf1) || !-e $outf1) &&
		       (!defined($no_outf2) || !-e $outf2) &&
		       (!defined($no_outf3) || !-e $outf3) &&
		       (!defined($no_outf4) || !-e $outf4) &&
		       (!defined($no_outf5) || !-e $outf5) &&
		       (!defined($no_outf5) || !-e $outf6) &&

		       (!defined($should_stdout_str) ||
			$should_stdout_str eq $test_output) &&
		       (!defined($should_stderr_str) ||
			$should_stderr_str eq $test_error) &&

		       (!defined($should_outf1_pat) ||
			(-e $outf1 && $test_outf1 =~ /$should_outf1_pat/)) &&
		       (!defined($should_outf2_pat) ||
			(-e $outf2 && $test_outf2 =~ /$should_outf2_pat/)) &&
		       (!defined($should_outf3_pat) ||
			(-e $outf3 && $test_outf3 =~ /$should_outf3_pat/)) &&
		       (!defined($should_outf4_pat) ||
			(-e $outf4 && $test_outf4 =~ /$should_outf4_pat/)) &&
		       (!defined($should_outf5_pat) ||
			(-e $outf5 && $test_outf5 =~ /$should_outf5_pat/)) &&
		       (!defined($should_outf6_pat) ||
			(-e $outf6 && $test_outf6 =~ /$should_outf6_pat/)) &&

		       (!defined($shouldnt_outf1_pat) ||
			(-e $outf1 && $test_outf1 !~ /$shouldnt_outf1_pat/)) &&
		       (!defined($shouldnt_outf2_pat) ||
			(-e $outf2 && $test_outf2 !~ /$shouldnt_outf2_pat/)) &&
		       (!defined($shouldnt_outf3_pat) ||
			(-e $outf3 && $test_outf3 !~ /$shouldnt_outf3_pat/)) &&
		       (!defined($shouldnt_outf4_pat) ||
			(-e $outf4 && $test_outf4 !~ /$shouldnt_outf4_pat/)) &&
		       (!defined($shouldnt_outf5_pat) ||
			(-e $outf5 && $test_outf5 !~ /$shouldnt_outf5_pat/)) &&
		       (!defined($shouldnt_outf6_pat) ||
			(-e $outf6 && $test_outf6 !~ /$shouldnt_outf6_pat/)) &&

		       (!defined($should_stdout_pat) ||

			(ref($should_stdout_pat) eq 'ARRAY' ?

			 #All patterns match
			 scalar(@$should_stdout_pat) ==
			 scalar(grep {$test_output =~ /$_/}
				@$should_stdout_pat) :

			 #The one pattern matches
			 $test_output =~ /$should_stdout_pat/)) &&

		       (!defined($shouldnt_stdout_pat) ||
			$test_output !~ /$shouldnt_stdout_pat/) &&

		       (!defined($should_stderr_pat) ||
			(ref($should_stderr_pat) eq 'ARRAY' ?

			 #All patterns match
			 scalar(@$should_stderr_pat) ==
			 scalar(grep {$test_error =~ /$_/}
				@$should_stderr_pat) :

			 #The one pattern matches
			 $test_error =~ /$should_stderr_pat/)) &&

		       (!defined($shouldnt_stderr_pat) ||
			$test_error !~ /$shouldnt_stderr_pat/) &&

		       (($exit_error == 0 && $exit_code == 0) ||
			($exit_error != 0 && $exit_code != 0)));
    ok($test_status,$test_description);

    #If the test failed while in debug mode, print a description of what went
    #wrong
    if(!$test_status && $DEBUG)
      {
	my $success = (($exit_error != 0  && $exit_code != 0) ||
		       ($exit_error == 0  && $exit_code == 0));
	my $expected = ($success ? [] : [['EXITCO',$exit_error]]);
	my $gotarray = ($success ? [] : [['EXITCO',$exit_code]]);
	foreach my $ary (['STDOUT','STDOUT',$test_output,$should_stdout_str,
			  $should_stdout_pat,$shouldnt_stdout_pat],
			 ['STDERR','STDERR',$test_error,$should_stderr_str,
			  $should_stderr_pat,$shouldnt_stderr_pat],
			 ['OUTF1 ',$outf1,$test_outf1,$should_outf1_str,
			  $should_outf1_pat,$shouldnt_outf1_pat],
			 ['OUTF2 ',$outf2,$test_outf2,$should_outf2_str,
			  $should_outf2_pat,$shouldnt_outf2_pat],
			 ['OUTF3 ',$outf3,$test_outf3,$should_outf3_str,
			  $should_outf3_pat,$shouldnt_outf3_pat],
			 ['OUTF4 ',$outf4,$test_outf4,$should_outf4_str,
			  $should_outf4_pat,$shouldnt_outf4_pat],
			 ['OUTF5 ',$outf5,$test_outf5,$should_outf5_str,
			  $should_outf5_pat,$shouldnt_outf5_pat],
			 ['OUTF6 ',$outf6,$test_outf6,$should_outf6_str,
			  $should_outf6_pat,$shouldnt_outf6_pat])
	  {
	    if(defined($ary->[3]))
	      {
		if((($ary->[1] eq 'STDOUT' || $ary->[1] eq 'STDERR' ||
		     -e $ary->[1]) && $ary->[2] ne $ary->[3]) ||
		   ($ary->[1] ne 'STDOUT' && $ary->[1] ne 'STDERR' &&
		    !-e $ary->[1]))
		  {
		    push(@$expected,[$ary->[0],$ary->[3]]);
		    push(@$gotarray,[$ary->[0],$ary->[2]]);
		  }
	      }
	    if(defined($ary->[4]))
	      {
		my @pats = ();
		if(ref($ary->[4]) eq 'ARRAY')
		  {push(@pats,@{$ary->[4]})}
		else
		  {push(@pats,$ary->[4])}
		foreach my $pat (@pats)
		  {
		    if((($ary->[1] eq 'STDOUT' || $ary->[1] eq 'STDERR' ||
			 -e $ary->[1]) && $ary->[2] !~ /$pat/) ||
		       ($ary->[1] ne 'STDOUT' && $ary->[1] ne 'STDERR' &&
			!-e $ary->[1]))
		      {
			push(@$expected,[$ary->[0],"/$pat/"]);
			push(@$gotarray,[$ary->[0],$ary->[2]]);
		      }
		  }
	      }
	    if(defined($ary->[5]))
	      {
		if((($ary->[1] eq 'STDOUT' || $ary->[1] eq 'STDERR' ||
		     -e $ary->[1]) && $ary->[2] =~ /$ary->[5]/) ||
		   ($ary->[1] ne 'STDOUT' && $ary->[1] ne 'STDERR' &&
		    !-e $ary->[1]))
		  {
		    push(@$expected,[$ary->[0],"!~ /$ary->[5]/"]);
		    push(@$gotarray,[$ary->[0],$ary->[2]]);
		  }
	      }
	  }

	debug3($expected,$gotarray,$test_status,$test_cmd);
      }

    #Clean up
    unless($no_clean)
      {
	#Clean up files:
	foreach my $tfile (grep {defined($_)} ($outf1,$outf2,$outf3,$outf4,
					       $outf5,$outf6,$test_errorf,
					       $out_script))
	  {
	    verbose("Cleaning $tfile");
	    unlink($tfile);
	  }
	#foreach my $tdir ($outd1,$outd2)
	#  {`rm -rf $tdir` if(defined($tdir) && $tdir ne '' && -e $tdir)}
      }
  }










if($starting_test > 1)
  {
    print STDERR "Skipping to test number $starting_test\n";
    $test_num = $starting_test - 1; #Will get incremented in the test code
    goto("TEST" . $starting_test);
  }


TEST1:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: Outdir per infile flag item";
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b c' -i 'd e f' --outdir '1 2 3' -o .test --verbose --dry-run%;
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(c,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef),(f,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([2/b.test],[],[],[undef]),([3/c.test],[],[],[undef]),([1/d.test],[],[],[undef]),([2/e.test],[],[],[undef]),([3/f.test],[],[],[undef])].%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_cmd     = "$test_cmd";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
unless($test_status)
  {
    $failures++;
  }
debug1();

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST2:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: STDIN gets a group & second file type split by group";
$test_pipe_in      = 'echo test text | ';
$test_cmd_opts     = q%-i "a b c" -j "1 2" --verbose --dry-run%;
$test_expected_str = q%Processing input file sets: [(-,1,undef,undef),(a,2,undef,undef),(b,2,undef,undef),(c,2,undef,undef)]%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_cmd     = "$test_cmd";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST3:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: STDIN gets a group & second file type associated by group";
$test_expected_str = q%Processing input file sets: [(-,1,undef,undef),(a,2,undef,undef),(b,2,undef,undef),(c,2,undef,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = 'echo test text | ';
$test_cmd_opts     = q%-i "a b c" -j 1 -j 2 --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_cmd     = "$test_cmd";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST4:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: This should associate STDIN with 1 & x; and a/b/c with 2 & y";
$test_expected_str = q%Processing input file sets: [(-,1,x,undef),(a,2,y,undef),(b,2,y,undef),(c,2,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = 'echo test text | ';
$test_cmd_opts     = q%-i - -i "a b c" -j 1 -j 2 -k x -k y --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST5:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: This should associate STDIN with 2 & y; and a/b/c with 1 & x";
$test_expected_str = q%Processing input file sets: [(a,1,x,undef),(b,1,x,undef),(c,1,x,undef),(-,2,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = 'echo test text | ';
$test_cmd_opts     = q%-i "a b c" -i - -j 1 -j 2 -k x -k y --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST6:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a and 2/d,e,f.";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef),(f,undef,undef,undef)] and output stubs: [([1/a.test1],[],[],[undef]),([2/d.test1],[],[],[undef]),([2/e.test1],[],[],[undef]),([2/f.test1],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a' --outdir '1' -i 'd e f' --outdir '2' -o .test1 --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST7:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a,b,c and 2/d";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(c,undef,undef,undef),(d,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([1/b.test],[],[],[undef]),([1/c.test],[],[],[undef]),([2/d.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b c' --outdir '1' -i 'd' --outdir '2' -o .test --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST8:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test,d.test  2/a.test,e.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(a,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([2/a.test],[],[],[undef]),([1/d.test],[],[],[undef]),([2/e.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a' -i 'd e' --outdir '1 2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST9:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test 2/d.test,e.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([2/d.test],[],[],[undef]),([2/e.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a' -i 'd e' --outdir '1' --outdir '2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST10:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test,b.test,c.test  2/d.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(c,undef,undef,undef),(d,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([1/b.test],[],[],[undef]),([1/c.test],[],[],[undef]),([2/d.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b c' -i 'd' --outdir '1 2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST11:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[a,d,y],[b,e,y],[c,f,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(a,d,y,undef),(b,e,y,undef),(c,f,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i 'a b c' -j '4' -j 'd e f' -k 'x y' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST12:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,x],[3,6,x],[a,d,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,x,undef),(3,6,x,undef),(a,d,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2 3' -i 'a' -j '4 5 6' -j 'd' -k 'x' -k 'y' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST13:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test,b.test  2/d.test,e.test,f.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef),(f,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([1/b.test],[],[],[undef]),([2/d.test],[],[],[undef]),([2/e.test],[],[],[undef]),([2/f.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b' -i 'd e f' --outdir '1 2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST14:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,x],[a,d,y],[b,e,y],[c,f,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,x,undef),(a,d,y,undef),(b,e,y,undef),(c,f,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2' -i 'a b c' -j '4 5' -j 'd e f' -k 'x y' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST15:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,x],[a,d,y],[a,e,y],[a,f,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,x,undef),(a,d,y,undef),(a,e,y,undef),(a,f,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2' -i 'a' -j '4 5' -j 'd e f' -k 'x' -k 'y' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST16:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test,b.test,c.test  2/d.test,e.test,f.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(c,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef),(f,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([1/b.test],[],[],[undef]),([1/c.test],[],[],[undef]),([2/d.test],[],[],[undef]),([2/e.test],[],[],[undef]),([2/f.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b c' --outdir '1' -i 'd e f' --outdir '2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);



TEST17:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test,d.test  2/b.test,e.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([2/b.test],[],[],[undef]),([1/d.test],[],[],[undef]),([2/e.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b' -i 'd e' --outdir '1 2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST18:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test,b.test 2/d.test,e.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([1/b.test],[],[],[undef]),([2/d.test],[],[],[undef]),([2/e.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b' -i 'd e' --outdir '1' --outdir '2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST19:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test,b.test,c.test 2/d.test,e.test,f.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(c,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef),(f,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([1/b.test],[],[],[undef]),([1/c.test],[],[],[undef]),([2/d.test],[],[],[undef]),([2/e.test],[],[],[undef]),([2/f.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b c' -i 'd e f' --outdir '1 2' -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST20:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: 1/a.test 2/b.test 3/c.test 4/d.test 5/e.test 6/f.test";
$test_expected_str = q%Processing input file sets: [(a,undef,undef,undef),(b,undef,undef,undef),(c,undef,undef,undef),(d,undef,undef,undef),(e,undef,undef,undef),(f,undef,undef,undef)] and output stubs: [([1/a.test],[],[],[undef]),([2/b.test],[],[],[undef]),([3/c.test],[],[],[undef]),([4/d.test],[],[],[undef]),([5/e.test],[],[],[undef]),([6/f.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'a b c' --outdir '1 2 3' -i 'd e f' --outdir '4 5 6'  -o .test --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST21:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,x],[3,6,x],[a,d,y],[b,e,y],[c,f,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,x,undef),(3,6,x,undef),(a,d,y,undef),(b,e,y,undef),(c,f,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2 3' -i 'a b c' -j '4 5 6' -j 'd e f' -k 'x y' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

exit(0) if($test_num == $ending_test);


TEST22:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,y],[3,6,z],[a,d,x],[b,e,y],[c,f,z]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,y,undef),(3,6,z,undef),(a,d,x,undef),(b,e,y,undef),(c,f,z,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2 3' -i 'a b c' -j '4 5 6' -j 'd e f' -k 'x y z' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST23:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,x],[3,6,x],[a,d,y],[b,e,y],[c,f,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,x,undef),(3,6,x,undef),(a,d,y,undef),(b,e,y,undef),(c,f,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2 3' -i 'a b c' -j '4 5 6' -j 'd e f' -k 'x' -k 'y' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST24:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,y],[3,6,z],[a,d,x],[b,e,y],[c,f,z]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,y,undef),(3,6,z,undef),(a,d,x,undef),(b,e,y,undef),(c,f,z,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2 3' -i 'a b c' -j '4 5 6' -j 'd e f' -k 'x' -k 'y' -k 'z' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST25:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,y],[3,6,z],[a,d,x],[b,e,y],[c,f,z]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(a,d,x,undef),(2,5,y,undef),(b,e,y,undef),(3,6,z,undef),(c,f,z,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 a' -i '2 b' -i '3 c' -j '4 d' -j '5 e' -j '6 f' -k 'x' -k 'y' -k 'z' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST26:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,a],[2,a]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(2,a,undef,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '2' -j 'a' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST27:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,a],[1,b]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --dry-run%;

#Test code


$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST28:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,y],[a,d,x],[b,e,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,y,undef),(a,d,x,undef),(b,e,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2' -i 'a b' -j '4 5' -j 'd e' -k 'x y' --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST29:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [[1,4,x],[2,5,x],[a,d,y],[b,e,y]]";
$test_expected_str = q%Processing input file sets: [(1,4,x,undef),(2,5,x,undef),(a,d,y,undef),(b,e,y,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2' -i 'a b' -j '4 5' -j 'd e' -k 'x' -k 'y' --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST30:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [1,A 7,B a,C x,D 2,E 8,F b,G y,H 3,I 9,J c,K z,L]";
$test_expected_str = q%Processing input file sets: [(1,A,undef,undef),(2,E,undef,undef),(3,I,undef,undef),(7,B,undef,undef),(8,F,undef,undef),(9,J,undef,undef),(a,C,undef,undef),(b,G,undef,undef),(c,K,undef,undef),(x,D,undef,undef),(y,H,undef,undef),(z,L,undef,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2 3' -i '7 8 9' -i 'a b c' -i 'x y z' -j 'A B C D' -j 'E F G H' -j 'I J K L' --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST31:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [1,A 7,B a,C x,D 2,E 8,E b,E y,E 3,I 9,J c,K z,L]";
$test_expected_str = q%Processing input file sets: [(1,A,undef,undef),(2,E,undef,undef),(3,I,undef,undef),(7,B,undef,undef),(8,E,undef,undef),(9,J,undef,undef),(a,C,undef,undef),(b,E,undef,undef),(c,K,undef,undef),(x,D,undef,undef),(y,E,undef,undef),(z,L,undef,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1 2 3' -i '7 8 9' -i 'a b c' -i 'x y z' -j 'A B C D' -j 'E' -j 'I J K L' --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST32:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "File and outdir combinations tests: [1,A 7,B a,C x,D 1,E 8,F b,G y,H 1,I 9,J c,K z,L]";
$test_expected_str = q%Processing input file sets: [(1,A,undef,undef),(1,E,undef,undef),(1,I,undef,undef),(7,B,undef,undef),(8,F,undef,undef),(9,J,undef,undef),(a,C,undef,undef),(b,G,undef,undef),(c,K,undef,undef),(x,D,undef,undef),(y,H,undef,undef),(z,L,undef,undef)] and output stubs: [([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef]),([-],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '7 8 9' -i 'a b c' -i 'x y z' -j 'A B C D' -j 'E F G H' -j 'I J K L' --dry-run%;

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

if($failures == 0)
  {$twooneseven = 1}

debug1();


exit(0) if($test_num == $ending_test);


TEST33:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Tests when not allowing merge output: [[1,a,unsupplied;1.test][1,b,unsupplied;1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([1.test],[],[],[undef]),([1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --dry-run --collision-mode merge%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --dry-run%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST34:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Tests when not allowing merge output: [[1,a,unsupplied;x/1.test][1,b,unsupplied;x/1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([x/1.test],[],[],[undef]),([x/1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --collision-mode merge%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST35:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Tests when not allowing merge output: quit with error";
$test_expected_str = q%Output file name conflict(s) detected: [1.test].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --dry-run --noagg%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST36:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Tests when not allowing merge output: quit with error";
$test_expected_str = q%Output file name conflict(s) detected: [x/1.test].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --noagg%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST37:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Tests when not allowing merge output: quit with error";
$test_expected_str = q%Offending file stub conflicts: [stub x/1 is generated by [z/1,y/1]].%;
my $test_expected_str2 = q%Offending file stub conflicts: [stub x/1 is generated by [y/1,z/1]].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'z/1' -i 'y/1' --outdir 'x' -o .test --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i 'z/1' -i 'y/1' --outdir 'x' -o .test --dry-run --noagg%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str) . '|' .
  quotemeta($test_expected_str2);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST38:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding of file names: [[1,a,unsupplied;1.test][1,b,unsupplied;1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([1.test],[],[],[undef]),([1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --collision-mode merge --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --dry-run --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST39:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding of file names: [[1,a,unsupplied;x/1.test][1,b,unsupplied;x/1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([x/1.test],[],[],[undef]),([x/1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --collision-mode merge --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST40:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding of file names: [[1,a,unsupplied;1.a.test][1,b,unsupplied;1.b.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([1.a.test],[],[],[undef]),([1.b.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --collision-mode resolve --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' -o .test --dry-run --noagg --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST41:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding of file names: [[1,a,unsupplied;x/1.a.test][1,b,unsupplied;x/1.b.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([x/1.a.test],[],[],[undef]),([x/1.b.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --collision-mode resolve --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --noagg --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST42:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding of file names: quit with error";
$test_expected_str = q%Offending file stub conflicts: [stub x/1 is generated by [z/1,y/1]].%;
$test_expected_str2 = q%Offending file stub conflicts: [stub x/1 is generated by [y/1,z/1]].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i 'z/1' -i 'y/1' --outdir 'x' -o .test --collision-mode resolve --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i 'z/1' -i 'y/1' --outdir 'x' -o .test --dry-run --noagg --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str) . '|' .
  quotemeta($test_expected_str2);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST43:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: [[1,a,unsupplied;1.test][1,b,unsupplied;1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([1.test],[],[],[undef]),([1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --collision-mode merge%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --agg%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST44:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: [[1,a,unsupplied;x/1.test][1,b,unsupplied;x/1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([x/1.test],[],[],[undef]),([x/1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --collision-mode merge --dry-run%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --agg --dry-run%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST45:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: quit with error";
$test_expected_str = q%Output file name conflict(s) detected: [1.test].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --collision-mode error%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --noagg%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST46:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: quit with error";
$test_expected_str = q%Output file name conflict(s) detected: [x/1.test].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --collision-mode error%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --noagg%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST47:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: [[1,a,unsupplied;1.test][1,b,unsupplied;1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([1.test],[],[],[undef]),([1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --collision-mode merge%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --agg --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST48:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: [[1,a,unsupplied;x/1.test][1,b,unsupplied;x/1.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([x/1.test],[],[],[undef]),([x/1.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --collision-mode merge%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --agg --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST49:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: [[1,a,unsupplied;1.a.test][1,b,unsupplied;1.b.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([1.a.test],[],[],[undef]),([1.b.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --collision-mode resolve%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' -o .test --dry-run --noagg --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();


exit(0) if($test_num == $ending_test);


TEST50:


$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Testing with compounding with user supplying duplicate input files: [[1,a,unsupplied;x/1.a.test][1,b,unsupplied;x/1.b.test]]";
$test_expected_str = q%Processing input file sets: [(1,a,undef,undef),(1,b,undef,undef)] and output stubs: [([x/1.a.test],[],[],[undef]),([x/1.b.test],[],[],[undef])].%;
$test_pipe_in      = '';
$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --collision-mode resolve%;
if($test_version eq '2.17')
  {$test_cmd_opts     = q%-i '1' -i '1' -j 'a' -j 'b' --outdir 'x' -o .test --dry-run --noagg --compound%}

#Test code

$test_cmd     = "$test_pipe_in $perl_call $test_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);
$failures++ unless($test_status);

#Evaluate result:
ok($test_status,$test_description);

debug1();

##
## If the first 33 tests passed and there have been 17 failures thus far, this
## is probably version 2.17, which needs different code to run
##

if($twooneseven && $failures == 17)
  {die "It looks like you might be testing version 2.17.  " .
	"Rerun this test as [perl perl_script_template.t '' 2.17]."}


##
## If test version is 2.17, stop here
##

if($test_version eq '2.17')
  {exit(0)}

##
## 51-79 deal with automatic selects, req. 34
##


exit(0) if($test_num == $ending_test);


TEST51:


#Requirement description:
#34. Put $select on automatic - don't open in select mode if an unclosed
#    handle in select mode exists.

$pattern           = '##TESTSLUG02';
$in_script         = $test_script;
$testfnum          = 1;
$testf             = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf`;
$testfnum++;
$testf2            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf2`;
$testfnum++;
$testf3            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf3`;
$testfnum++;
$testf4            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf4`;
$testfnum++;
$testf5            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf5`;
$testfnum++;
$testf6            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf6`;
$testfnum++;
$testf7            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf7`;
$testfnum++;
$testf8            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf8`;
$testfnum++;
$testf9            = "$test_script.test_dummy_infile$testfnum.txt";
`echo $testfnum > $testf9`;
$sub_test_num      = 1;
$test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Req34. Select automatically test 1";
$test_expected_str = q%Only 1 output handle can be selected at a time.%;
$test_pipe_in      = '';
$test_cmd_opts     = qq%-i $test_script -o .test51 --overwrite%;
$test_cmd          = '';
$out_script        = '';
$out_script        = "$in_script.test$test_num.req34_$sub_test_num.pl";
$code              = '';
$outf1             = '';
$outf2             = '';
$outf3             = '';
$outf4             = '';
$outf5             = '';
$outf6             = '';
$outf7             = '';
$outf8             = '';
$outf9             = '';
$outf1             = "$out_script.one.txt";
$outf2             = "$out_script.two.txt";
$code = << "EOT";
openOut(*ONE,"$outf1");
select(ONE);
openOut(*TWO,"$outf2");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_cmd     = "$test_pipe_in $perl_call $out_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);

#Evaluate result:
ok($test_status,$test_description);

unless($test_status)
  {
    $failures++;
  }

debug1();


exit(0) if($test_num == $ending_test);


TEST52:


#Requirement description:
#34. Put $select on automatic - don't open in implicit select mode if an
#    unclosed handle in select mode exists.  Explicit is fine.

$test_num++;
$sub_test_num++;
$test_status       = 0;
$test_output       = '';
$test_pattern      = '';
$test_description  = "Req34. Select automatically test 2";
$test_expected_str = q%Only 1 output handle can be selected at a time.%;
$test_pipe_in      = '';
$test_cmd_opts     = qq%-i $test_script -o .test52 --overwrite%;
$test_cmd          = '';
$outf1             = "$out_script.one.txt";
$outf2             = "$out_script.two.txt";
$out_script        = "$in_script.test$test_num.req34_$sub_test_num.pl";
$code = << "EOT";
openOut(*ONE,"$outf1");
select(ONE);
openOut(*TWO,"$outf2");
print("1\n");           #To prevent runtime warning
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_cmd     = "$test_pipe_in $perl_call $out_script $test_cmd_opts $test_cmd_append";
$test_output  = `$test_cmd`;
$test_pattern = quotemeta($test_expected_str);
$test_status  = ($test_output =~ /$test_pattern/);

#Evaluate result:
ok($test_status,$test_description);

unless($test_status)
  {$failures++}

debug1();



##
## 53-79 have a special setup:
##

$outf1            = '';
$outf2            = '';
$test_errorf      = '';
#my $test_output  = '';
$test_error       = '';
$test_output1     = '';
$test_output2     = '';
$test_stdout      = '';
$test_should1     = '';
$test_should2     = '';
$test_warn_str    = "Only 1 output handle can be selected at a time.";
$test_warn_pat    = quotemeta($test_warn_str);
$test_cmd_opts    = ' --noheader --debug --overwrite';
$test_desc_def    = "Req34. Select automatically";
my $save_no_clean = $no_clean;
$no_clean         = 1;

$test_output      = `$test_cmd`;


exit(0) if($test_num == $ending_test);


TEST53:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2",1);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = '';

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n3\n5\n";
$test_should1 = "2\n";
$test_should2 = "4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

debug2();


unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile (grep {defined($_)} ($outf1,$outf2,$test_errorf,
					   $out_script))
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST54:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2");
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n3\n5\n";
$test_should1 = "2\n";
$test_should2 = "4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

if(!$test_status)
  {debug("TEST$test_num: $out_script -i $testf $test_cmd_opts 2> ",
	 "$test_errorf")}

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST55:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2",0);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n3\n4\n5\n";
$test_should1 = "2\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST56:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
openOut(*TWO,"$outf2",1);
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n4\n5\n";
$test_should1 = "2\n";
$test_should2 = "3\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST57:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
openOut(*TWO,"$outf2",1);
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n5\n";
$test_should1 = "2\n";
$test_should2 = "3\n4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST58:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
openOut(*TWO,"$outf2");
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n5\n";
$test_should1 = "2\n3\n4\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   =~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST59:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
openOut(*TWO,"$outf2");
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n4\n5\n";
$test_should1 = "2\n3\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   =~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST60:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
openOut(*TWO,"$outf2",0);
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n5\n";
$test_should1 = "2\n3\n4\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST61:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",1);
print("2\\n");
openOut(*TWO,"$outf2",0);
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n4\n5\n";
$test_should1 = "2\n3\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST62:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2",1);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n3\n5\n";
$test_should1 = "2\n";
$test_should2 = "4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST63:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2");
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n3\n5\n";
$test_should1 = "2\n";
$test_should2 = "4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST64:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2",0);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n3\n4\n5\n";
$test_should1 = "2\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST65:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
openOut(*TWO,"$outf2",1);
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n4\n5\n";
$test_should1 = "2\n";
$test_should2 = "3\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST66:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
openOut(*TWO,"$outf2",1);
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n5\n";
$test_should1 = "2\n";
$test_should2 = "3\n4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST67:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
openOut(*TWO,"$outf2");
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n5\n";
$test_should1 = "2\n3\n4\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   =~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST68:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
openOut(*TWO,"$outf2");
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n4\n5\n";
$test_should1 = "2\n3\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   =~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST69:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
openOut(*TWO,"$outf2",0);
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n5\n";
$test_should1 = "2\n3\n4\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST70:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1");
print("2\\n");
openOut(*TWO,"$outf2",0);
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n4\n5\n";
$test_should1 = "2\n3\n";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST71:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2",1);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n3\n5\n";
$test_should1 = "";
$test_should2 = "4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST72:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2");
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n3\n5\n";
$test_should1 = "";
$test_should2 = "4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST73:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
closeOut(*ONE);
print("3\\n");
openOut(*TWO,"$outf2",0);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n3\n4\n5\n";
$test_should1 = "";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST74:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
openOut(*TWO,"$outf2",1);
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n4\n5\n";
$test_should1 = "";
$test_should2 = "3\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST75:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
openOut(*TWO,"$outf2",1);
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n5\n";
$test_should1 = "";
$test_should2 = "3\n4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST76:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
openOut(*TWO,"$outf2");
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n4\n5\n";
$test_should1 = "";
$test_should2 = "3\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST77:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
openOut(*TWO,"$outf2");
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n5\n";
$test_should1 = "";
$test_should2 = "3\n4\n";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST78:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
openOut(*TWO,"$outf2",0);
print("3\\n");
closeOut(*TWO);
print("4\\n");
closeOut(*ONE);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n3\n4\n5\n";
$test_should1 = "";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

debug2();


exit(0) if($test_num == $ending_test);


TEST79:


$test_num++;
$sub_test_num++;
$test_description = $test_desc_def . " test $sub_test_num";
$out_script = "$in_script.test$test_num.req34_$sub_test_num.pl";
$outf1      = "$out_script.one.txt";
$outf2      = "$out_script.two.txt";
$code = << "EOT";
print("1\\n");
openOut(*ONE,"$outf1",0);
print("2\\n");
openOut(*TWO,"$outf2",0);
print("3\\n");
closeOut(*ONE);
print("4\\n");
closeOut(*TWO);
print("5\\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

$test_stdout  = "1\n2\n3\n4\n5\n";
$test_should1 = "";
$test_should2 = "";

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INTWO,$outf2);
$test_output2 = join('',<INTWO>);
close(INTWO);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output  eq $test_stdout &&
                $test_output1 eq $test_should1 &&
                $test_output2 eq $test_should2 &&
                $test_error   !~ /$test_warn_pat/);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }

unless($no_clean)
  {
    #Tests for requirement 34 done, so clean up:
    unlink($testf);
  }



exit(0) if($test_num == $ending_test);


TEST80:


$test_num++;
$test_description = "Req36. Print hostname, time, user, & directory in header of opened file.";
$out_script    = "$in_script.test$test_num.req36_1.pl";
$outf1         = "$out_script.one.txt";
$test_cmd_opts = "--header --overwrite";
$userpat       = quotemeta("#User: $ENV{USER}");
$timepat       = quotemeta("#Time: ") . '\S+';
$hostpat       = quotemeta("#Host: $ENV{HOST}");
$dirpat        = quotemeta("#Directory: $ENV{PWD}");
$code = << "EOT";
openOut(*ONE,"$outf1",0);
print ONE ("TEST\n");
closeOut(*ONE);
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts 2> $test_errorf";
$test_output  = `$test_cmd`;

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output1 =~ /$userpat/ &&
                $test_output1 =~ /$timepat/ &&
                $test_output1 =~ /$hostpat/ &&
	        $test_output1 =~ /$dirpat/  &&
	        $test_error !~ /error/i);

#Evaluate result:
ok($test_status,$test_description);

if(!$test_status)
  {
    $test_output1 =~ s/\n(?=.)/\n\t                  /g;
    debug("TEST$test_num: $test_cmd\n",
          "\tExpected File1:  [/$userpat/,\n",
	  "\t                  /$timepat/,\n",
	  "\t                  /$dirpat/,\n",
	  "\t                  /$hostpat/]\n",
          "\tGot:             [$test_output1]\n",
	  "\tExpected STDERR: []\n",
	  "\tGot:             [$test_error]");
  }

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$test_errorf,$out_script,$testf)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST81:


$test_num++;
$test_description = "Req36. Print hostname, time, user, & directory in header of redirected file.";
$out_script       = "$in_script.test$test_num.req36_2.pl";
$outf1            = "$out_script.one.txt";
$test_cmd_opts    = "--header --overwrite $debug_flag";
$userpat          = quotemeta("#User: $ENV{USER}");
$timepat          = quotemeta("#Time: ") . '\S+';
$hostpat          = quotemeta("#Host: $ENV{HOST}");
$dirpat           = quotemeta("#Directory: $ENV{PWD}");
$code = << "EOT";
print("1\n");
EOT

insertTemplateCode($code,$pattern,$in_script,$out_script);

$test_errorf  = "$out_script.err.txt";

$test_cmd     = "$perl_call $out_script -i $testf $test_cmd_opts > $outf1 2> $test_errorf";
$test_output  = `$test_cmd`;

open(INONE,$outf1);
$test_output1 = join('',<INONE>);
close(INONE);

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_status = ($test_output1 =~ /$userpat/ &&
                $test_output1 =~ /$timepat/ &&
                $test_output1 =~ /$hostpat/ &&
	        $test_output1 =~ /$dirpat/  &&
	        $test_error   !~ /error/i);

#Evaluate result:
ok($test_status,$test_description);

unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$test_errorf,$out_script,$testf)
      {unlink($tfile)}
  }

if(!$test_status)
  {
    $test_output1 =~ s/\n(?=.)/\n\t                  /g;
    debug("TEST$test_num: $test_cmd\n",
          "\tExpected STDOUT: [/$userpat/,\n",
	  "\t                  /$timepat/,\n",
	  "\t                  /$dirpat/,\n",
	  "\t                  /$hostpat/]\n",
          "\tGot:             [$test_output1]");
  }


exit(0) if($test_num == $ending_test);


TEST82:


#Describe the test
$test_num++;
$sub_test_num     = 1;
$test_description = "Req38. Add quiet opt to openIn & track for use in closeIn.  quiet = 1";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$outf1            = "";
$outf2            = "";
$test_errorf      = "$out_script.err.txt";

#Create/edit the script to add the test code
$code = << "EOT";
openIn(*ONE,"$testf2",1);
scalar(<ONE>);
closeIn(*ONE);
EOT
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Runt he command and gather the output
$test_output   = `$test_cmd`;
open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

#Create a string or pattern for the expected result
$err_verbose1_pat = quotemeta($testf2);


#Evaluate the result
$test_status = ($test_error !~ /$err_verbose1_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['STDERR',"!~ /$err_verbose1_pat/"]],[['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST83:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req38. Add quiet opt to openIn & track for use in closeIn.  quiet = 0";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$outf1            = "";
$outf2            = "";
$test_errorf      = "$out_script.err.txt";
#global $testf file (contains the string "test\n")

#Create/edit the script to add the test code
$code = << "EOT";
openIn(*ONE,"$testf2",0);
scalar(<ONE>);
closeIn(*ONE);
EOT
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Runt he command and gather the output
$test_output   = `$test_cmd`;
open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

#Create a string or pattern for the expected result
$err_verbose1_pat = quotemeta("[$testf2] Opened input file.");
$err_verbose2_pat = quotemeta("[$testf2] Input file done.");

#Evaluate the result
$test_status = ($test_error =~ /$err_verbose1_pat/ &&
	        $test_error =~ /$err_verbose2_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['STDERR',"/$err_verbose1_pat/ && /$err_verbose2_pat/"]],
	  [['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST84:


#Prepare for the following series of tests for requirement 40, which requires a
#bit more code

if(-e $source_script)
  {$test_script = createTestScript2()}
if(!defined($test_script) || !-e $test_script)
  {die(join('',("Unable to parse script template [$source_script].  The ",
		"template may have been overwritten.  Please retrieve a ",
		"fresh copy from the repository.")))}

$code = << 'EOT';
while(nextFileCombo())
  {
    my($output_file) = getOutfile($sufftype1);
    openOut(*OUTPUT,$output_file) || next;

    foreach my $input_file (getInfile())
      {
        openIn(*INPUT,$input_file) || next;

        #For each line in the current input file
        while(getLine(*INPUT))
	  {print}

	closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT


#Describe the test
$test_num++;
$sub_test_num = 1;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: simple merge";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';
$test_outf7 = '';
$test_outf8 = '';
$test_outf9 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -o .out --collision-mode merge --noheader --overwrite";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

if(open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n1\n";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_outf7_str    = "";
$should_outf8_str    = "";
$should_outf9_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$should_outf6_pat    = '';
$should_outf7_pat    = '';
$should_outf8_pat    = '';
$should_outf9_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$shouldnt_outf6_pat  = '';
$shouldnt_outf7_pat  = '';
$shouldnt_outf8_pat  = '';
$shouldnt_outf9_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',$should_outf1_str],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',$test_outf1],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST85:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: simple resolve error";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -o .out --collision-mode resolve --noheader";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"=~ /$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST86:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: simple error";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -o .out --collision-mode error --noheader";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"=~ /$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST87:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: double merge";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf $testf2 $testf2' -o .out --collision-mode merge --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n1\n";
$should_outf2_str    = "2\n2\n";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str      &&
	        $test_outf2  eq $should_outf2_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST88:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: double resolve";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf $testf2 $testf2' -o .out --collision-mode resolve --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1 && !-e $outf2);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['OUTF2 ',"!-e $outf2"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['OUTF2 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST89:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: double error";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf $testf2 $testf2' -o .out --collision-mode error --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1 && !-e $outf2);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['OUTF2 ',"!-e $outf2"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['OUTF2 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST90:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 2-types";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -k $testf2 -o .out --collision-mode merge --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n2\n1\n2\n";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',$should_outf1_str],
	   ['STDOUT',$shouldnt_stderr_pat],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',$test_outf1],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST91:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 2-types";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf2;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf1            = "$splitf1.$splitf2.out";
$outf2            = "$testf.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -k $testf2 -o .out --collision-mode resolve --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1 && !-e $outf2);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['OUTF2 ',"!-e $outf2"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['OUTF2 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST92:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 2-types";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -k $testf2 -o .out --collision-mode error --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST93:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 2-types 2";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -k '$testf2 $testf2' -o .out --collision-mode merge --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n2\n1\n2\n";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',$should_outf1_str],
	   ['STDOUT',$shouldnt_stderr_pat],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',$test_outf1],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST94:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 2-types 2";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf2;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf1            = "$splitf1.$splitf2.out";
$outf2            = "$testf.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -k '$testf2 $testf2' -o .out --collision-mode resolve --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1 && !-e $outf2);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['OUTF2 ',"!-e $outf2"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['OUTF2 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST95:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 2-types 2";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -k '$testf2 $testf2' -o .out --collision-mode error --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST96:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 3-types";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -k '$testf2 $testf2' -j $testf3 -o .out --collision-mode merge --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n3\n2\n1\n3\n2\n";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',$should_outf1_str],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',$test_outf1],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST97:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 3-types";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf2;
$splitf3          = $testf3;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$splitf3 =~ s/.*\///;
$outf1            = "$splitf1.$splitf2.splitf3.out";
$outf2            = "$testf.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -k '$testf2 $testf2' -j $testf3 -o .out --collision-mode resolve --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1 && !-e $outf2);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['OUTF2 ',"!-e $outf2"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['OUTF2 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST98:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 3-types";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -k '$testf2 $testf2' -j $testf3 -o .out --collision-mode error --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
	        !-e $outf1);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST99:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 3-types, 2 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -j '$testf $testf2' -k $testf3 -o .out --collision-mode merge --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n1\n3\n1\n2\n3\n";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',$should_outf1_str],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',$test_outf1],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST100:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 3-types, 2 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf2;
$splitf3          = $testf3;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$splitf3 =~ s/.*\///;
$outf1            = "$splitf1.$splitf1.out";
$outf2            = "$splitf1.$splitf2.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -j '$testf $testf2' -k $testf3 -o .out --collision-mode resolve --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n1\n3\n";
$should_outf2_str    = "1\n2\n3\n";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
		-e $outf1 && -e $outf2 &&
	        $test_outf1  eq $should_outf1_str      &&
	        $test_outf2  eq $should_outf2_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"-e $outf1"],
	   ['OUTF2 ',"-e $outf2"],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['OUTF2 ',(-e $outf2 ? 'exists' : 'does not exist')],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST101:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 3-types, 2 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf2;
$splitf3          = $testf3;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$splitf3 =~ s/.*\///;
$outf1            = "$splitf1.out";
$outf2            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i $testf -j '$testf $testf2' -k $testf3 -o .out --collision-mode error --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str   &&
	        $test_error  =~ /$should_stderr_pat/ &&
		!-e $outf1);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',"!-e $outf1"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['OUTF1 ',(-e $outf1 ? 'exists' : 'does not exist')],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$test_errorf,$out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST102:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 3-pairs & 1 pair, 2 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "$testf3.out";
$outf4            = "$testf4.out";
$outf5            = "$testf5.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -i '$testf $testf3' -i '$testf4 $testf5' -k '$testf6 $testf7' -o .out --collision-mode merge --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

$test_outf5 = '';
if(-e $outf5 && open(IN,$outf5))
  {
    $test_outf5 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n6\n1\n6\n";
$should_outf2_str    = "2\n7\n";
$should_outf3_str    = "3\n7\n";
$should_outf4_str    = "4\n6\n";
$should_outf5_str    = "5\n7\n";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
		$test_outf1  eq $should_outf1_str      &&
		$test_outf2  eq $should_outf2_str      &&
		$test_outf3  eq $should_outf3_str      &&
		$test_outf4  eq $should_outf4_str      &&
		$test_outf5  eq $should_outf5_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['OUTF3 ',$should_outf3_str],
	   ['OUTF4 ',$should_outf4_str],
	   ['OUTF5 ',$should_outf5_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['OUTF3 ',$test_outf3],
	   ['OUTF4 ',$test_outf4],
	   ['OUTF5 ',$test_outf5],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST103:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 3-pairs & 1 pair, 2 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "";
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -i '$testf $testf3' -i '$testf4 $testf5' -k '$testf6 $testf7' -o .out --collision-mode resolve --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

$test_outf5 = '';
if(-e $outf5 && open(IN,$outf5))
  {
    $test_outf5 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST104:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 3-pairs & 1 pair, 2 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "";
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -i '$testf $testf3' -i '$testf4 $testf5' -k '$testf6 $testf7' -o .out --collision-mode resolve --noheader --verbose";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

open(INERR,$test_errorf);
$test_error = join('',<INERR>);
close(INERR);

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

$test_outf5 = '';
if(-e $outf5 && open(IN,$outf5))
  {
    $test_outf5 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($test_output eq $should_stdout_str &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST105:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 3-pairs & 1 pair, 1 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "$testf3.out";
$outf4            = "$testf4.out";
$outf5            = "$testf5.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -i '$testf2 $testf3' -i '$testf4 $testf5' -k '$testf6 $testf7' -o .out --collision-mode merge";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output = `$test_cmd`;

$exit_code = $?;

$test_errorf = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

$test_outf5 = '';
if(-e $outf5 && open(IN,$outf5))
  {
    $test_outf5 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n6\n1\n7\n";
$should_outf2_str    = "2\n6\n";
$should_outf3_str    = "3\n7\n";
$should_outf4_str    = "4\n6\n";
$should_outf5_str    = "5\n7\n";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$should_stdout_pat   = '';
$should_stderr_pat   = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$shouldnt_stdout_pat = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($? == 0 &&
		$test_output eq $should_stdout_str     &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
		$test_outf1  eq $should_outf1_str      &&
		$test_outf2  eq $should_outf2_str      &&
		$test_outf3  eq $should_outf3_str      &&
		$test_outf4  eq $should_outf4_str      &&
		$test_outf5  eq $should_outf5_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['OUTF3 ',$should_outf3_str],
	   ['OUTF4 ',$should_outf4_str],
	   ['OUTF5 ',$should_outf5_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['OUTF3 ',$test_outf3],
	   ['OUTF4 ',$test_outf4],
	   ['OUTF5 ',$test_outf5],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST106:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 3-pairs & 1 pair, 1 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf2;
$splitf3          = $testf3;
$splitf4          = $testf4;
$splitf5          = $testf5;
$splitf6          = $testf6;
$splitf7          = $testf7;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$splitf3 =~ s/.*\///;
$splitf4 =~ s/.*\///;
$splitf5 =~ s/.*\///;
$splitf6 =~ s/.*\///;
$splitf7 =~ s/.*\///;
$outf1            = "$splitf1.$splitf6.out";
$outf2            = "$splitf1.$splitf7.out";
$outf3            = "$splitf2.$splitf6.out";
$outf4            = "$splitf3.$splitf7.out";
$outf5            = "$splitf4.$splitf6.out";
$outf6            = "$splitf5.$splitf7.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -i '$testf2 $testf3' -i '$testf4 $testf5' -k '$testf6 $testf7' -o .out --collision-mode resolve";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

$test_outf5 = '';
if(-e $outf5 && open(IN,$outf5))
  {
    $test_outf5 = join('',<IN>);
    close(IN);
  }

$test_outf6 = '';
if(-e $outf6 && open(IN,$outf6))
  {
    $test_outf6 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n6\n";
$should_outf2_str    = "1\n7\n";
$should_outf3_str    = "2\n6\n";
$should_outf4_str    = "3\n7\n";
$should_outf5_str    = "4\n6\n";
$should_outf6_str    = "5\n7\n";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$should_outf6_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$shouldnt_outf6_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = 'ERROR\d';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($exit_code == 0 &&
		$test_outf1  eq $should_outf1_str   &&
		$test_outf2  eq $should_outf2_str   &&
		$test_outf3  eq $should_outf3_str   &&
		$test_outf4  eq $should_outf4_str   &&
		$test_outf5  eq $should_outf5_str   &&
		$test_outf6  eq $should_outf6_str   &&
		$test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['OUTF3 ',$should_outf3_str],
	   ['OUTF4 ',$should_outf4_str],
	   ['OUTF5 ',$should_outf5_str],
	   ['OUTF6 ',$should_outf6_str],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['OUTF3 ',$test_outf3],
	   ['OUTF4 ',$test_outf4],
	   ['OUTF5 ',$test_outf5],
	   ['OUTF6 ',$test_outf6],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST107:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 3-pairs & 1 pair, 1 with same file";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "";
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf' -i '$testf2 $testf3' -i '$testf4 $testf5' -k '$testf6 $testf7' -o .out --collision-mode error";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

$test_outf5 = '';
if(-e $outf5 && open(IN,$outf5))
  {
    $test_outf5 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($exit_code != 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','!0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST108:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 2 pairs of files, first reused & gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -k '$testf3 $testf4' -k '$testf5 $testf6' -o .out --collision-mode merge";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n3\n1\n5\n";
$should_outf2_str    = "2\n4\n2\n6\n";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($exit_code   == 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str &&
	        $test_outf2  eq $should_outf2_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST109:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 2 pairs of files, first reused & gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf3;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf1            = "$splitf1.$splitf2.out";
$splitf1          = $testf;
$splitf2          = $testf5;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf2            = "$splitf1.$splitf2.out";
$splitf1          = $testf2;
$splitf2          = $testf4;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf3            = "$splitf1.$splitf2.out";
$splitf1          = $testf2;
$splitf2          = $testf6;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf4            = "$splitf1.$splitf2.out";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -k '$testf3 $testf4' -k '$testf5 $testf6' -o .out --collision-mode resolve";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n3\n";
$should_outf2_str    = "1\n5\n";
$should_outf3_str    = "2\n4\n";
$should_outf4_str    = "2\n6\n";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($exit_code   == 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str &&
	        $test_outf2  eq $should_outf2_str &&
	        $test_outf3  eq $should_outf3_str &&
	        $test_outf4  eq $should_outf4_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['OUTF3 ',$should_outf3_str],
	   ['OUTF4 ',$should_outf4_str]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['OUTF3 ',$test_outf3],
	   ['OUTF4 ',$test_outf4]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST110:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 2 pairs of files, first reused & gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -k '$testf3 $testf4' -k '$testf5 $testf6' -o .out --collision-mode error";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($exit_code   != 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','!0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST111:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 2 pairs of files, first separated & reused & gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf' -i '$testf2' -k '$testf3 $testf4' -k '$testf5 $testf6' -o .out --collision-mode merge";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n3\n1\n4\n";
$should_outf2_str    = "2\n5\n2\n6\n";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($exit_code   == 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str &&
	        $test_outf2  eq $should_outf2_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST112:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 2 pairs of files, first separated & reused & gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf3;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf1            = "$splitf1.$splitf2.out";
$splitf1          = $testf;
$splitf2          = $testf4;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf2            = "$splitf1.$splitf2.out";
$splitf1          = $testf2;
$splitf2          = $testf5;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf3            = "$splitf1.$splitf2.out";
$splitf1          = $testf2;
$splitf2          = $testf6;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf4            = "$splitf1.$splitf2.out";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf' -i '$testf2' -k '$testf3 $testf4' -k '$testf5 $testf6' -o .out --collision-mode resolve";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n3\n";
$should_outf2_str    = "1\n4\n";
$should_outf3_str    = "2\n5\n";
$should_outf4_str    = "2\n6\n";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($exit_code   == 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str &&
	        $test_outf2  eq $should_outf2_str &&
	        $test_outf3  eq $should_outf3_str &&
	        $test_outf4  eq $should_outf4_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['OUTF3 ',$should_outf3_str],
	   ['OUTF4 ',$should_outf4_str]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['OUTF3 ',$test_outf3],
	   ['OUTF4 ',$test_outf4]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST113:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 2 pairs of files, first separated & reused & gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf' -i '$testf2' -k '$testf3 $testf4' -k '$testf5 $testf6' -o .out --collision-mode error";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }

#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($exit_code   != 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','!0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST114:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: merge 2 groups of diff nums of files, first gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "";
$outf4            = "";
$outf5            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -k '$testf3 $testf4 $testf5' -o .out --collision-mode merge";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n3\n1\n4\n1\n5\n";
$should_outf2_str    = "2\n3\n2\n4\n2\n5\n";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($exit_code   == 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str &&
	        $test_outf2  eq $should_outf2_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST115:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: resolve 2 groups of diff nums of files, first gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$splitf1          = $testf;
$splitf2          = $testf3;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf1            = "$splitf1.$splitf2.out";
$splitf1          = $testf;
$splitf2          = $testf4;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf2            = "$splitf1.$splitf2.out";
$splitf1          = $testf;
$splitf2          = $testf5;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf3            = "$splitf1.$splitf2.out";
$splitf1          = $testf2;
$splitf2          = $testf3;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf4            = "$splitf1.$splitf2.out";
$splitf1          = $testf2;
$splitf2          = $testf4;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf5            = "$splitf1.$splitf2.out";
$splitf1          = $testf2;
$splitf2          = $testf5;
$splitf1 =~ s/.*\///;
$splitf2 =~ s/.*\///;
$outf6            = "$splitf1.$splitf2.out";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -k '$testf3 $testf4 $testf5' -o .out --collision-mode resolve";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

$test_outf1 = '';
if(-e $outf1 && open(IN,$outf1))
  {
    $test_outf1 = join('',<IN>);
    close(IN);
  }

$test_outf2 = '';
if(-e $outf2 && open(IN,$outf2))
  {
    $test_outf2 = join('',<IN>);
    close(IN);
  }

$test_outf3 = '';
if(-e $outf3 && open(IN,$outf3))
  {
    $test_outf3 = join('',<IN>);
    close(IN);
  }

$test_outf4 = '';
if(-e $outf4 && open(IN,$outf4))
  {
    $test_outf4 = join('',<IN>);
    close(IN);
  }

$test_outf5 = '';
if(-e $outf5 && open(IN,$outf5))
  {
    $test_outf5 = join('',<IN>);
    close(IN);
  }

$test_outf6 = '';
if(-e $outf6 && open(IN,$outf6))
  {
    $test_outf6 = join('',<IN>);
    close(IN);
  }

#Create a string or pattern for the expected result
$should_outf1_str    = "1\n3\n";
$should_outf2_str    = "1\n4\n";
$should_outf3_str    = "1\n5\n";
$should_outf4_str    = "2\n3\n";
$should_outf5_str    = "2\n4\n";
$should_outf6_str    = "2\n5\n";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';

#Evaluate the result
$test_status = ($exit_code   == 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  !~ /$shouldnt_stderr_pat/ &&
	        $test_outf1  eq $should_outf1_str &&
	        $test_outf2  eq $should_outf2_str &&
	        $test_outf3  eq $should_outf3_str &&
	        $test_outf4  eq $should_outf4_str &&
	        $test_outf5  eq $should_outf5_str &&
	        $test_outf6  eq $should_outf6_str);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"],
	   ['OUTF1 ',$should_outf1_str],
	   ['OUTF2 ',$should_outf2_str],
	   ['OUTF3 ',$should_outf3_str],
	   ['OUTF4 ',$should_outf4_str],
	   ['OUTF5 ',$should_outf5_str],
	   ['OUTF6 ',$should_outf6_str]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error],
	   ['OUTF1 ',$test_outf1],
	   ['OUTF2 ',$test_outf2],
	   ['OUTF3 ',$test_outf3],
	   ['OUTF4 ',$test_outf4],
	   ['OUTF5 ',$test_outf5],
	   ['OUTF6 ',$test_outf6]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }


exit(0) if($test_num == $ending_test);


TEST116:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req40. Output modes when file names conflict: merge, resolve, or error. Test $sub_test_num: error 2 groups of diff nums of files, first gets suffix";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$testf.out";
$outf2            = "$testf2.out";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the command
$test_cmd_opts = "-i '$testf $testf2' -k '$testf3 $testf4 $testf5' -o .out --collision-mode error";
$test_cmd      = "$perl_call $out_script --noheader $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';

#Evaluate the result
$test_status = ($exit_code   != 0 &&
		$test_output eq $should_stdout_str &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','!0'],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
  }

###
### Requirement 44 Tests: Have --overwrite supplied twice (or more) safely*
###                       deletes the output directory.  *Deletes only if all
###                       files have a header from this or another template
###                       script whose creation time is before the start of the
###                       script.
###

$sub_test_num = 0;
#I can use the same code as the previous round of tests
$testdnum = 1;
$testd1 = "$test_script.test_outdir$testdnum.dir";
$outd1  = "$testd1.out";
#my($inodenum,$newinodenum);
$testdnum++;
$testd2 = "$test_script.test_outdir$testdnum.dir";
$outd2  = "$testd2.out";
#my($inodenum2,$newinodenum2,$inodenum3,$newinodenum3,$inodenum4,$newinodenum4);


exit(0) if($test_num == $ending_test);


TEST117:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: pre-existing empty directory & no overwrite flag";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create a pre-existing directory and get its inode number to check later
mkdir($outd1);
$inodenum = (stat($outd1))[1];

#Create the command
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out";
$test_cmd      = "$perl_call $out_script --header $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum         = (stat($outd1))[1];

#Evaluate the result
$test_status = ($inodenum    eq $newinodenum &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"iNode#: [$inodenum]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',$newinodenum],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1)
      {`rm -rf $tdir`}
  }


exit(0) if($test_num == $ending_test);


TEST118:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: pre-existing empty directory & 1 overwrite flag";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create a pre-existing directory and sleep to let the number of seconds since
#run be different
mkdir($outd1);
$inodenum = (stat($outd1))[1];

#Create the command
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --overwrite";
$test_cmd      = "$perl_call $out_script --header $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum = (stat($outd1))[1];

#Evaluate the result
$test_status = ($inodenum    eq $newinodenum &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"iNode#: [$inodenum]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',$newinodenum],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1)
      {`rm -rf $tdir`}
  }


exit(0) if($test_num == $ending_test);


TEST119:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: pre-existing empty directory & 2 overwrite flags";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create a pre-existing directory and sleep to let the number of seconds since
#run be different
mkdir($outd1);
$inodenum = (stat($outd1))[1];


#Create the command
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --overwrite --overwrite";
$test_cmd      = "$perl_call $out_script --header $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum = (stat($outd1))[1];

#Evaluate the result
$test_status = (-e $outf1 &&
		$inodenum    ne $newinodenum &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"SHOULD EXIST: [$outf1]"],
	   ['OUTD1 ',"iNode# != [$inodenum]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',(-e $outf1 ? 'EXISTS' : 'DOES NOT EXIST')],
	   ['OUTD1 ',$newinodenum],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1)
      {`rm -rf $tdir`}
  }


exit(0) if($test_num == $ending_test);


TEST120:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: pre-existing empty directory & 3 overwrite flags";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create a pre-existing directory and sleep to let the number of seconds since
#run be different
mkdir($outd1);
$inodenum = (stat($outd1))[1];


#Create the command
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --overwrite --overwrite --overwrite";
$test_cmd      = "$perl_call $out_script --header $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum         = (stat($outd1))[1];

#Evaluate the result
$test_status = (-e $outf1 &&
		$inodenum    ne $newinodenum &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"SHOULD EXIST: [$outf1]"],
	   ['OUTD1 ',"iNode# != [$inodenum]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',(-e $outf1 ? 'EXISTS' : 'DOES NOT EXIST')],
	   ['OUTD1 ',$newinodenum],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1)
      {`rm -rf $tdir`}
  }


exit(0) if($test_num == $ending_test);


TEST121:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: pre-existing empty directory & --overwrite 2";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create a pre-existing directory and sleep to let the number of seconds since
#run be different
mkdir($outd1);
$inodenum = (stat($outd1))[1];


#Create the command
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --overwrite --overwrite --overwrite";
$test_cmd      = "$perl_call $out_script --header $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum         = (stat($outd1))[1];

#Evaluate the result
$test_status = (-e $outf1 &&
		$inodenum    ne $newinodenum &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"SHOULD EXIST: [$outf1]"],
	   ['OUTD1 ',"iNode# != [$inodenum]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',(-e $outf1 ? 'EXISTS' : 'DOES NOT EXIST')],
	   ['OUTD1 ',$newinodenum],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1)
      {`rm -rf $tdir`}
  }


exit(0) if($test_num == $ending_test);


TEST122:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: 2 pre-existing empty directories & --overwrite 2";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "$outd2/$testf2.out";
$outf2            =~ s%/\./%/%g;
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);
`rm -rf $outd2` if($outd2 ne '' && -e $outd2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create a pre-existing directory and sleep to let the number of seconds since
#run be different
mkdir($outd1);
$inodenum = (stat($outd1))[1];
mkdir($outd2);
$inodenum2 = (stat($outd2))[1];

#Create the command
$test_cmd_opts = "-i $testf -i $testf2 --outdir $outd1 --outdir $outd2 -o .out --overwrite 2";
$test_cmd      = "$perl_call $out_script --header $test_cmd_opts 2> $test_errorf";

#Run the command and gather the output
$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum         = (stat($outd1))[1];
$newinodenum2        = (stat($outd2))[1];

#Evaluate the result
$test_status = (-e $outf1 && -e $outf2 &&
		$inodenum    ne $newinodenum &&
		$inodenum2   ne $newinodenum2 &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"SHOULD EXIST: [$outf1]"],
	   ['OUTF2 ',"SHOULD EXIST: [$outf2]"],
	   ['OUTD1 ',"iNode# != [$inodenum]"],
	   ['OUTD2 ',"iNode# != [$inodenum2]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',(-e $outf1 ? 'EXISTS' : 'DOES NOT EXIST')],
	   ['OUTF2 ',(-e $outf2 ? 'EXISTS' : 'DOES NOT EXIST')],
	   ['OUTD1 ',$newinodenum],
	   ['OUTD2 ',$newinodenum2],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1,$outd2)
      {`rm -rf $tdir`}
  }


exit(0) if($test_num == $ending_test);


TEST123:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: previous run of script with same outdir/outfile with header";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);
`rm -rf $outd2` if($outd2 ne '' && -e $outd2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the first command
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --header";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command to create the directory/file
`$test_cmd`;

#Get the unique ID for the directory
$inodenum = (stat($outd1))[1];

#Create the second command (the one we're testing)
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --overwrite 2 --header";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum         = (stat($outd1))[1];

#Evaluate the result
$test_status = (-e $outf1 &&
		$inodenum    ne $newinodenum &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"SHOULD EXIST: [$outf1]"],
	   ['OUTD1 ',"iNode# != [$inodenum]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',(-e $outf1 ? 'EXISTS' : 'DOES NOT EXIST')],
	   ['OUTD1 ',$newinodenum],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1,$outd2)
      {`rm -rf $tdir` if(defined($tdir) && $tdir ne '' && -e $tdir)}
  }


exit(0) if($test_num == $ending_test);


TEST124:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: previous run of script with same outdir/outfile with no header";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "";
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);
`rm -rf $outd2` if($outd2 ne '' && -e $outd2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the first command
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --noheader";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command to create the directory/file
`$test_cmd`;

#Get the unique ID for the directory
$inodenum = (stat($outd1))[1];
#Get the unique ID for the file
$inodenum2 = (stat($outf1))[1];

#Create the second command (the one we're testing)
$test_cmd_opts = "-i $testf --outdir $outd1 -o .out --overwrite 2 --header";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';
$newinodenum         = (stat($outd1))[1];
$newinodenum2        = (stat($outf1))[1];

#Evaluate the result
$test_status = ($inodenum    eq $newinodenum &&
		$inodenum2   eq $newinodenum2 &&
		$exit_code   != 0 &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"iNode# == [$inodenum2]"],
	   ['OUTD1 ',"iNode# == [$inodenum]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',$newinodenum2],
	   ['OUTD1 ',$newinodenum],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1,$outd2)
      {`rm -rf $tdir` if(defined($tdir) && $tdir ne '' && -e $tdir)}
  }


exit(0) if($test_num == $ending_test);


TEST125:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: previous run of script with same 2 outdirs/outfiles with header";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "$outd2/$testf2.out";
$outf2            =~ s%/\./%/%g;
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);
`rm -rf $outd2` if($outd2 ne '' && -e $outd2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the first command
$test_cmd_opts = "-i $testf -i $testf2 --outdir $outd1 --outdir $outd2 -o .out --header";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command to create the directory/file
`$test_cmd`;

#Get the unique ID for the directory
$inodenum = (stat($outd1))[1];
$inodenum2 = (stat($outd2))[1];

#Create the second command (the one we're testing)
$test_cmd_opts = "-i $testf -i $testf2 --outdir $outd1 --outdir $outd2 -o .out --overwrite 2 --header";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = '';
$shouldnt_stderr_pat = 'ERROR\d';
$newinodenum         = (stat($outd1))[1];
$newinodenum2        = (stat($outd2))[1];

#Evaluate the result
$test_status = ($inodenum    ne $newinodenum &&
		$inodenum2   ne $newinodenum2 &&
		$exit_code   == 0 &&
	        $test_error  !~ /$shouldnt_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTD1 ',"iNode# != [$inodenum]"],
	   ['OUTD2 ',"iNode# != [$inodenum2]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"!~ /$shouldnt_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTD1 ',$newinodenum],
	   ['OUTD2 ',$newinodenum2],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1,$outd2)
      {`rm -rf $tdir` if(defined($tdir) && $tdir ne '' && -e $tdir)}
  }


exit(0) if($test_num == $ending_test);


TEST126:


#Describe the test
$test_num++;
$sub_test_num++;
$test_description = "Req44. --overwrite >1 safely deletes dir. Test $sub_test_num: previous run of script with same 2 outdirs/outfiles with no headers";

#Name the files involved
$out_script       = "$in_script.test$test_num.$sub_test_num.pl";
$test_errorf      = "$out_script.err.txt";
$outf1            = "$outd1/$testf.out";
$outf1            =~ s%/\./%/%g;
$outf2            = "$outd2/$testf2.out";
$outf2            =~ s%/\./%/%g;
$outf3            = "";
$outf4            = "";
$outf5            = "";
$outf6            = "";
#global $testf file (contains the string "test\n")

#Prepare the variables that will hold the output
$test_error = '';
$test_outf1 = '';
$test_outf2 = '';
$test_outf3 = '';
$test_outf4 = '';
$test_outf5 = '';
$test_outf6 = '';

#Clean up any previous tests
unlink($outf1) if($outf1 ne '' && -e $outf1);
unlink($outf2) if($outf2 ne '' && -e $outf2);
unlink($outf3) if($outf3 ne '' && -e $outf3);
unlink($outf4) if($outf4 ne '' && -e $outf4);
unlink($outf5) if($outf5 ne '' && -e $outf5);
unlink($outf6) if($outf6 ne '' && -e $outf6);
`rm -rf $outd1` if($outd1 ne '' && -e $outd1);
`rm -rf $outd2` if($outd2 ne '' && -e $outd2);

#Create/edit the script to add the test code
insertTemplateCode($code,$pattern,$in_script,$out_script);

#Create the first command
$test_cmd_opts = "-i $testf -i $testf2 --outdir $outd1 --outdir $outd2 -o .out --noheader";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

#Run the command to create the directory/file
`$test_cmd`;

#Get the unique ID for the directory
$inodenum = (stat($outd1))[1];
$inodenum2 = (stat($outd2))[1];
#Get the unique ID for the file
$inodenum3 = (stat($outf1))[1];
$inodenum4 = (stat($outf2))[1];

#Create the second command (the one we're testing)
$test_cmd_opts = "-i $testf -i $testf2 --outdir $outd1 --outdir $outd2 -o .out --overwrite 2 --header";
$test_cmd      = "$perl_call $out_script $test_cmd_opts 2> $test_errorf";

$test_output   = `$test_cmd`;

$exit_code = $?;

$test_error = '';
if(-e $test_errorf && open(INERR,$test_errorf))
  {
    $test_error = join('',<INERR>);
    close(INERR);
  }

#$test_outf1 = '';
#if(-e $outf1 && open(IN,$outf1))
#  {
#    $test_outf1 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf2 = '';
#if(-e $outf2 && open(IN,$outf2))
#  {
#    $test_outf2 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf3 = '';
#if(-e $outf3 && open(IN,$outf3))
#  {
#    $test_outf3 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf4 = '';
#if(-e $outf4 && open(IN,$outf4))
#  {
#    $test_outf4 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf5 = '';
#if(-e $outf5 && open(IN,$outf5))
#  {
#    $test_outf5 = join('',<IN>);
#    close(IN);
#  }
#
#$test_outf6 = '';
#if(-e $outf6 && open(IN,$outf6))
#  {
#    $test_outf6 = join('',<IN>);
#    close(IN);
#  }


#Create a string or pattern for the expected result
$should_outf1_str    = "";
$should_outf2_str    = "";
$should_outf3_str    = "";
$should_outf4_str    = "";
$should_outf5_str    = "";
$should_outf6_str    = "";
$should_stdout_str   = "";
$should_stderr_str   = "";
$should_outf1_pat    = '';
$should_outf2_pat    = '';
$should_outf3_pat    = '';
$should_outf4_pat    = '';
$should_outf5_pat    = '';
$shouldnt_outf1_pat  = '';
$shouldnt_outf2_pat  = '';
$shouldnt_outf3_pat  = '';
$shouldnt_outf4_pat  = '';
$shouldnt_outf5_pat  = '';
$should_stdout_pat   = '';
$shouldnt_stdout_pat = '';
$should_stderr_pat   = 'ERROR\d';
$shouldnt_stderr_pat = '';
$newinodenum         = (stat($outd1))[1];
$newinodenum2        = (stat($outd2))[1];
$newinodenum3        = (stat($outf1))[1];
$newinodenum4        = (stat($outf2))[1];

#Evaluate the result
$test_status = ($inodenum    eq $newinodenum &&
		$inodenum2   eq $newinodenum2 &&
		$inodenum3   eq $newinodenum3 &&
		$inodenum4   eq $newinodenum4 &&
		$exit_code   != 0 &&
	        $test_error  =~ /$should_stderr_pat/);
ok($test_status,$test_description);

#If the test failed while in debug mode, print a description of what went wrong
if(!$test_status && $DEBUG)
  {debug3([['EXITCO','0'],
	   ['OUTF1 ',"iNode# == [$inodenum3]"],
	   ['OUTF2 ',"iNode# == [$inodenum4]"],
	   ['OUTD1 ',"iNode# == [$inodenum]"],
	   ['OUTD2 ',"iNode# == [$inodenum2]"],
	   ['STDOUT',$should_stdout_str],
	   ['STDERR',"/$should_stderr_pat/"]],
	  [['EXITCO',$exit_code],
	   ['OUTF1 ',$newinodenum3],
	   ['OUTF2 ',$newinodenum4],
	   ['OUTD1 ',$newinodenum],
	   ['OUTD2 ',$newinodenum2],
	   ['STDOUT',$test_output],
	   ['STDERR',$test_error]])}

#Clean up
unless($no_clean)
  {
    #Clean up files:
    foreach my $tfile ($outf1,$outf2,$outf3,$outf4,$outf5,$outf6,$test_errorf,
		       $out_script)
      {unlink($tfile)}
    foreach my $tdir ($outd1,$outd2)
      {`rm -rf $tdir` if(defined($tdir) && $tdir ne '' && -e $tdir)}
  }



exit(0) if($test_num == $ending_test);


TEST127:


#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = 126;

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Required test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid1,
                           PAIR_RELAT  => 'ONETOONE');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);
    my $input_file2 = getInfile($fid2);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    if(defined($input_file2))
      {
        openIn(*INPUT,$input_file2) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 1:0 files with success',
       $in_script,
       $testf,undef,undef,undef,undef,undef,
       "$testf.out",undef,undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i $testf -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST128:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 1:1 files with success',
       $in_script,
       $testf,$testf2,undef,undef,undef,undef,
       "$testf.out",undef,undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i $testf -j $testf2 -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n2\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);


exit(0) if($test_num == $ending_test);


TEST129:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 2:0 files with success',
       $in_script,
       $testf,$testf2,$testf3,undef,undef,undef,
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf $testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);


exit(0) if($test_num == $ending_test);


TEST130:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 2:2 files with success',
       $in_script,
       $testf,$testf2,$testf3,undef,undef,undef,
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf $testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST131:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 1:2 files with error',
       $in_script,
       $testf,$testf2,$testf3,undef,undef,undef,
       undef,undef,undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf' -j '$testf2 $testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       1,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST132:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 2:1 files with error',
       $in_script,
       $testf,$testf2,$testf3,undef,undef,undef,
       undef,undef,undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf $testf2' -j '$testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       1,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST133:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 1,1:0 files with success',
       $in_script,
       $testf,$testf2,undef,undef,undef,undef,
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf' -i '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST134:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 1,1:1,1 files with success',
       $in_script,
       $testf,$testf2,undef,undef,undef,undef,
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf' -i '$testf2' -j $testf3 -j $testf4 -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST135:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 2,2:0 files with success',
       $in_script,
       $testf,$testf2,$testf3,$testf4,undef,undef,
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf $testf2' -i '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n","2\n","3\n","4\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST136:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 2,2:2,2 files with success',
       $in_script,
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       $code,'##TESTSLUG01',
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5 $testf' -j " .
       "'$testf6 $testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       undef,undef,"1\n5\n","2\n1\n","3\n6\n","4\n2\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error)
       0,
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST137:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 1,1:2,2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3 $testf4' -j '$testf5 $testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST138:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 2,2:1,2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5' -j '$testf6 " .
       "$testf6' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST139:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional file type supplying 2:2,2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -j '$testf5 $testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST140:

#Describe the test
$test_num++;
$sub_test_num++;

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Required test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid1,
                           PAIR_RELAT  => 'ONETOMANY');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);
    my $input_file2 = getInfile($fid2);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    if(defined($input_file2))
      {
        openIn(*INPUT,$input_file2) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 1:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST141:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 1:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n2\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST142:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST143:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n3\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST144:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 1:2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2 $testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST145:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2:2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST146:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 1,1:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST147:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 1,1:1,1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3' -j '$testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST148:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2,2:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n","3\n","4\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST149:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2,2:1,1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5' -j '$testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n5\n","2\n5\n","3\n6\n","4\n6\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST150:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2,2:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5' -o .out " .
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n5\n","2\n5\n","3\n5\n","4\n5\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST151:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 1,1:2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST152:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2,2:2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5 $testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n5\n","2\n6\n","3\n5\n","4\n6\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST153:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 1,1:2,2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3 $testf4' -j '$testf5 $testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST154:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2,2:1,2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5' " .
       "-j '$testf6 $testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST155:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:M optional file type supplying 2,2:3 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' " .
       "-j '$testf5 $testf6 $testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST156:

#Describe the test
$test_num++;
$sub_test_num++;

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Required test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid1,
                           PAIR_RELAT  => 'ONETOONEORMANY');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);
    my $input_file2 = getInfile($fid2);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    if(defined($input_file2))
      {
        openIn(*INPUT,$input_file2) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 1:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST157:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 1:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n2\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST158:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST159:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n3\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST160:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2:2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST161:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 1:2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2 $testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST162:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2:3 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4 $testf5' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST163:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 3:2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2 $testf3' -j '$testf4 $testf5' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST164:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 1,1:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST165:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 1,1:1,1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3' -j '$testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST166:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2,1:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out",undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n","3\n",undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST167:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 3,2:1,2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out","$testf5.out",
       undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2 $testf3' -i '$testf4 $testf5' -j '$testf6' " .
       "-j '$testf $testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n6\n","2\n6\n","3\n6\n","4\n1\n","5\n2\n",undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST168:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2,2:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3' '$testf4' -j '$testf5' -o .out " .
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n5\n","2\n5\n","3\n5\n","4\n5\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST169:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 1,1:2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST170:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2,2:2,2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5 $testf6' " .
       "-j '$testf $testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n5\n","2\n6\n","3\n1\n","4\n2\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST171:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2,2:1,2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out","$testf4.out",undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5' " .
       "-j '$testf6 $testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n5\n","2\n5\n","3\n6\n","4\n1\n",undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST172:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 1,1:2,2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3 $testf4' -j '$testf5 $testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST173:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1orM optional file type supplying 2,2:3 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' " .
       "-j '$testf5 $testf6 $testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST174:

#Describe the test
$test_num++;
$sub_test_num++;

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Required test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid1,
                           PAIR_RELAT  => 'ONETOONE');

my $fid3 = addInfileOption(GETOPTKEY   => 'k=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid2,
                           PAIR_RELAT  => 'ONETOONE');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);
    my $input_file2 = getInfile($fid2);
    my $input_file3 = getInfile($fid3);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    if(defined($input_file2))
      {
        openIn(*INPUT,$input_file2) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    if(defined($input_file3))
      {
        openIn(*INPUT,$input_file3) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1:0:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST175:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1:1:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n2\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST176:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1:1:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2' -k '$testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n2\n3\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST177:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2:2:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST178:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2:2:2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -k '$testf5 $testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n5\n","2\n4\n6\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST179:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1:2:1 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2 $testf3' -k '$testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST180:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2:2:1 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -k '$testf5' -o .out " .
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST181:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1:0:1 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -k '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST182:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1,1:0:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST183:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1,1:1,1:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3' -j '$testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST184:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1,2:1,2:1,2 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out",undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2 $testf3' -j '$testf4' -j '$testf5 $testf6' " .
       "-k '$testf2' -k '$testf3 $testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n4\n2\n","2\n5\n3\n","3\n6\n1\n",undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST185:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2,2:1,1:0 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5' -j '$testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST186:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2,2:2,1:0 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3 $testf4' -j '$testf5 $testf6' " .
       "-j '$testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST187:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1,2:1,2:1,1 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2 $testf3' -j '$testf4' -j '$testf5 $testf6' " .
       "-k '$testf' -k '$testf2' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST188:

#Describe the test
$test_num++;
$sub_test_num++;

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Required test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid1,
                           PAIR_RELAT  => 'ONETOONE');

my $fid3 = addInfileOption(GETOPTKEY   => 'k=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid1,
                           PAIR_RELAT  => 'ONETOMANY');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);
    my $input_file2 = getInfile($fid2);
    my $input_file3 = getInfile($fid3);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    if(defined($input_file2))
      {
        openIn(*INPUT,$input_file2) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    if(defined($input_file3))
      {
        openIn(*INPUT,$input_file3) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1:0:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST189:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2:2:0 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n4\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST190:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2:2:1 files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -k '$testf5' -o .out " .
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n5\n","2\n4\n5\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST191:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 1:2:1 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2 $testf3' -k '$testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST192:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2:1:1 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3' -k '$testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST193:

#Describe the test
$test_num++;
$sub_test_num++;

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second 1:1 optional and third 1:1 (with second) file types ' .
       'supplying 2:2:2 files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,$testf6,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -k '$testf5 $testf6' " .
       "-o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST194:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Required test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Optional test infile opt.',
                           DETAIL_DESC => 'My Detailed Description.',
                           FORMAT_DESC => 'My input file format description.',
                           PAIR_WITH   => $fid1,
                           PAIR_RELAT  => 'ONE');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);
    my $input_file2 = getInfile($fid2);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    if(defined($input_file2))
      {
        openIn(*INPUT,$input_file2) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 1:0 ' .
       'files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST195:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 2:1 ' .
       'files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n3\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST196:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 1,1:1 ' .
       'files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n3\n","2\n3\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST197:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 1,1:1 ' .
       'files with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out","$testf3.out",undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3' -j '$testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n4\n","2\n4\n","3\n4\n",undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST198:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 1:2 ' .
       'files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -j '$testf2 $testf3' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST199:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 2:2 ' .
       'files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST200:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 1,1:2 ' .
       'files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -i '$testf2' -j '$testf3 $testf4' -o .out --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST201:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '126&141';

#$in_script = createTestScript3();
#$code = << 'EOT';

test6f($test_num,
       $sub_test_num,
       'second optional file type with "relationship" "1" supplying 2,1:1,1 ' .
       'files with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,$testf3,$testf4,$testf5,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf $testf2' -i '$testf3' -j '$testf4' -j '$testf5' -o .out " .
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST202:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
EOT
$code .= << "EOT";
                           DEFAULT     => '$testf',
EOT
$code .= << 'EOT';
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching default glob string for required file type not user ' .
       'supplied with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST203:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
EOT
$code .= << "EOT";
                           DEFAULT     => ['$testf'],
EOT
$code .= << 'EOT';
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching default glob array for required file type not user ' .
       'supplied with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST204:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
EOT
$code .= << "EOT";
                           DEFAULT     => [['$testf']],
EOT
$code .= << 'EOT';
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching default glob 2D array for required file type not user ' .
       'supplied with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST205:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
EOT
$code .= << "EOT";
                           DEFAULT     => [[['$testf']]],
EOT
$code .= << 'EOT';
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching default glob 3D array for required file type not user ' .
       'supplied with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST206:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           DEFAULT     => 'does_not_exist.txt',
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'non-matching default glob string for required file type not user ' .
       'supplied with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST207:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           DEFAULT     => ['does_not_exist.txt',
EOT
$code .= << "EOT";
                                           '$testf'],
EOT
$code .= << 'EOT';
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching & non-matching default glob strings for required file ' .
       'type not user supplied with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST208:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 0,
EOT
$code .= << "EOT";
                           DEFAULT     => '$testf',
EOT
$code .= << 'EOT';
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching default glob string for optional file type not user ' .
       'supplied with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST209:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Required test infile opt.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j=s',
                           REQUIRED    => 0,
                           DEFAULT     => 'does_not_exist.txt',
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);
    my $input_file2 = getInfile($fid2);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    if(defined($input_file2))
      {
        openIn(*INPUT,$input_file2) || next;
        while(getLine(*INPUT))
          {print}
        closeIn(*INPUT);
      }

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching required user-supplied file type & non-matching default ' .
       'optional not user supplied file type with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST210:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '155';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 0,
                           DEFAULT     => ['does_not_exist.txt',
EOT
$code .= << "EOT";
                                           '$testf'],
EOT
$code .= << 'EOT';
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Default test infile opt.');

while(nextFileCombo())
  {
    my $input_file1 = getInfile($fid1);

    my($output_file) = getOutfile();
    openOut(*OUTPUT,$output_file) || next;

    openIn(*INPUT,$input_file1) || next;
    while(getLine(*INPUT))
      {print}
    closeIn(*INPUT);

    closeOut(*OUTPUT);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'matching & non-matching default glob strings for optional file ' .
       'type not user supplied with error',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST211:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           SMRY_DESC   => 'Default test infile opt.');

my $sid1 = addOutfileSuffixOption(GETOPTKEY   => 'o=s',
                                  FILETYPEID  => $fid1,
                                  REQUIRED    => 0,
                                  PRIMARY     => 0,
                                  SMRY_DESC   => 'Default test outfile opt.');

my $input_file1  = getInfile($fid1,1);
my($output_file) = getOutfile($sid1);
if(!defined($output_file))
  {exit(0)}
exit(1);
EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, no default, and not supplied, outf undefined',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST212:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           SMRY_DESC   => 'Default test infile opt.');

my $sid1 = addOutfileSuffixOption(GETOPTKEY   => 'o=s',
                                  FILETYPEID  => $fid1,
                                  REQUIRED    => 0,
                                  PRIMARY     => 0,
                                  SMRY_DESC   => 'Default test outfile opt.');

my $input_file1  = getInfile($fid1,1);
my($output_file) = getOutfile($sid1);
openOut($output_file);
quit(0);
EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, no default, and not supplied, openOut dies',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST213:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           SMRY_DESC   => 'Default test infile opt.');

my $sid1 = addOutfileSuffixOption(GETOPTKEY   => 'o=s',
                                  FILETYPEID  => $fid1,
                                  DEFAULT     => '.out',
                                  REQUIRED    => 0,
                                  PRIMARY     => 0,
                                  SMRY_DESC   => 'Default test outfile opt.');

my $input_file1  = getInfile($fid1,1);
my($output_file) = getOutfile($sid1);
openOut(*OUTPUT,$output_file);
openIn(*INPUT,$input_file1) || next;
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, a default, and not supplied, default output',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST214:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

#$in_script = createTestScript3();
#$code = << 'EOT';
#my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
#                           REQUIRED    => 1,
#                           SMRY_DESC   => 'Default test infile opt.');
#
#my $sid1 = addOutfileSuffixOption(GETOPTKEY   => 'o=s',
#                                  FILETYPEID  => $fid1,
#                                  DEFAULT     => '.out',
#                                  REQUIRED    => 0,
#                                  PRIMARY     => 0,
#                                  SMRY_DESC   => 'Default test outfile opt.');
#
#my $input_file1  = getInfile($fid1,1);
#my($output_file) = getOutfile($sid1);
#openOut(*OUTPUT,$output_file);
#openIn(*INPUT,$input_file1) || next;
#while(getLine(*INPUT))
#  {print}
#closeIn(*INPUT);
#closeOut(*OUTPUT);
#EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, has default, and is supplied, supplied val ' .
       'used',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.test",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .test --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST215:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           SMRY_DESC   => 'Default test infile opt.');

my $sid1 = addOutfileSuffixOption(GETOPTKEY   => 'o=s',
                                  FILETYPEID  => $fid1,
                                  DEFAULT     => '.out',
                                  REQUIRED    => 0,
                                  PRIMARY     => 0,
                                  SMRY_DESC   => 'Default test outfile opt.');

my $input_file1  = getInfile($fid1,1);
my($output_file) = getOutfile($sid1);
openOut(*OUTPUT,$output_file);
openIn(*INPUT,$input_file1) || next;
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT
$code .= << "EOT";
if(-e "$testf.out")
  {
    print STDERR "File $testf.out appears to exist.\n";
    quit(1);
  }
EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, has default, and is supplied, default ' .
       'ignored',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.test","$testf.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .test --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST216:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           SMRY_DESC   => 'Default test infile opt.');

my $sid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 0,
                            PRIMARY     => 0,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1  = getInfile($fid1,1);
my($output_file) = getOutfile($sid1);
if(defined($output_file))
  {
    print STDERR "output_file: [$output_file] should not be defined.\n";
    quit(1);
  }
quit(0);
EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, no default, and not supplied, outfile ' .
       'undefined',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST217:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           SMRY_DESC   => 'Default test infile opt.');

my $sid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 0,
                            PRIMARY     => 0,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1  = getInfile($fid1,1);
my($output_file) = getOutfile($sid1);
if(defined($output_file) && $output_file ne '/dev/null')
  {
    print STDERR ("Expected output_file to be /dev/null, but it's: ",
                  "[$output_file].\n");
    quit(1);
  }
quit(0);
EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, no default, not supplied, and --force ' .
       'supplied, outfile is /dev/null',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --force --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "1",'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST218:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i|input-file=s',
                           REQUIRED    => 1,
                           SMRY_DESC   => 'Default test infile opt.');

my $sid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 0,
                            PRIMARY     => 0,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1  = getInfile($fid1,1);
my($output_file) = getOutfile($sid1);
if($output_file ne '-')
  {
    print STDERR "Expected output_file to be '-', but got: [$output_file].\n";
    quit(1);
  }
openOut(*OUTPUT,$output_file);
openIn(*INPUT,$input_file1) || next;
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'When suffix not primary, no default, not supplied, and --force x 2 ' .
       'supplied, output to STDOUT',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --force --force --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST219:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => '$testf.out',
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1 = getInfile();
my($output_file) = getOutfile($fid1);
openOut(*OUTPUT,$output_file) || quit(1);
openIn(*INPUT,$input_file1) || quit(2);
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'matching default outfile for required file type not user supplied ' .
       'with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST220:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => ['$testf.out'],
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1 = getInfile();
my($output_file) = getOutfile($fid1);
openOut(*OUTPUT,$output_file) || quit(1);
openIn(*INPUT,$input_file1) || quit(2);
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'matching default outfile in array for required file type not user ' .
       'supplied with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST221:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => [['$testf.out']],
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1 = getInfile();
my($output_file) = getOutfile($fid1);
openOut(*OUTPUT,$output_file) || quit(1);
openIn(*INPUT,$input_file1) || quit(2);
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'matching default outfile in 2D array for required file type not ' .
       'user supplied with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST222:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => [[['$testf.out']]],
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1 = getInfile();
my($output_file) = getOutfile($fid1);
openOut(*OUTPUT,$output_file) || quit(1);
openIn(*INPUT,$input_file1) || quit(2);
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'matching default outfile in 3D array for required file type not ' .
       'user supplied with failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST223:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => '$testf2',
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $input_file1 = getInfile();
my($output_file) = getOutfile($fid1);
openOut(*OUTPUT,$output_file) || quit(1);
openIn(*INPUT,$input_file1) || quit(2);
while(getLine(*INPUT))
  {print}
closeIn(*INPUT);
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'existing default outfile for required file type not user supplied ' .
       'with failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST224:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => ['does_not_exist.out','$testf2'],
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $output_file = getOutfile($fid1);
EOT

test6f($test_num,
       $sub_test_num,
       '1 existing and 1 not existing default outfile for required file ' .
       'type not user supplied with failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST225:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile1=s',
                            REQUIRED    => 1,
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $fid2 = addOutfileOption(GETOPTKEY   => 'outfile2=s',
                            REQUIRED    => 0,
EOT
$code .= << "EOT";
                            DEFAULT     => '$testf2.out',
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $output_file = getOutfile($fid1);
openOut(*OUT1,$output_file);
print OUT1 ("1\n");
closeOut(*OUT1);
$output_file = getOutfile($fid2);
openOut(*OUT2,$output_file);
print OUT2 ("2\n");
closeOut(*OUT2);
EOT

test6f($test_num,
       $sub_test_num,
       'supply valid required outfile, no default and no optional outfile ' .
       'with valid default with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--outfile1 '$testf.out' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n","2\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST226:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 0,
EOT
$code .= << "EOT";
                            DEFAULT     => ['does_not_exist.out','$testf2'],
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $output_file = getOutfile($fid1);
EOT

test6f($test_num,
       $sub_test_num,
       'supply 1 existing, 1 not existing default outfile for optional file ' .
       'with failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,$testf2,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST227:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '159';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 0,
EOT
$code .= << "EOT";
                            DEFAULT     => ['does_not_exist.out','$testf2'],
EOT
$code .= << 'EOT';
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $output_file = getOutfile($fid1);
openOut(*OUT1,$output_file);
print OUT1 ("1\n");
closeOut(*OUT1);
EOT

test6f($test_num,
       $sub_test_num,
       'supply 1 existing, 1 not existing default outfile for optional file ' .
       'and user supplied valid outfile with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf2,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf3.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--outfile '$testf3.out' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST228:

#Describe the test
$test_num++;
$sub_test_num = 9;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => '$testf.out',
EOT
$code .= << 'EOT';
                            PRIMARY     => 0,
                            SMRY_DESC   => 'Default test outfile opt.');

my($output_file) = getOutfile($fid1);
openOut(*OUTPUT,$output_file) || quit(1);
print "1\n";
closeOut(*OUTPUT);
EOT

test6f($test_num,
       $sub_test_num,
       'non-primary outfile with valid default and no supplied file with ' .
       'success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"1\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST229:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 1,
EOT
$code .= << "EOT";
                            DEFAULT     => '$testf.out',
EOT
$code .= << 'EOT';
                            PRIMARY     => 0,
                            SMRY_DESC   => 'Default test outfile opt.');

my($output_file) = getOutfile($fid1);
openOut(*OUTPUT,$output_file) || quit(1);
print "1\n";
closeOut(*OUTPUT);
EOT
$code .= << "EOT";
if(-e '$testf.out')
  {quit(1)}
EOT

test6f($test_num,
       $sub_test_num,
       'non-primary outfile with valid default and different supplied file ' .
       'with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--outfile '$testf2.out' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,"1\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST230:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '154';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addOutfileOption(GETOPTKEY   => 'outfile=s',
                            REQUIRED    => 0,
                            PRIMARY     => 1,
                            SMRY_DESC   => 'Default test outfile opt.');

my $output_file = getOutfile($fid1);
openOut(*OUT1,$output_file);
print OUT1 ("1\n");
closeOut(*OUT1);
EOT

test6f($test_num,
       $sub_test_num,
       'non-primary outfile with valid default and different supplied file ' .
       'with success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out","$testf2.out",undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--outfile '$testf2.out' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,"1\n",undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);


exit(0) if($test_num == $ending_test);


TEST231:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'i=s',
                           REQUIRED    => 1,
                           PRIMARY     => 1,
                           SMRY_DESC   => 'Test duplicate opts.');

my $fid2 = addInfileOption(GETOPTKEY   => 'j|i=s',
                           REQUIRED    => 0,
                           PRIMARY     => 0,
                           SMRY_DESC   => 'Test duplicate opts.');

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Add 2 infile flags containing a duplicate with failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST232:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $noheader = 0;
addOption(GETOPTKEY => 'noheader!',
          GETOPTVAL => \$noheader);

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Add option that matches header option (with no prepended) with ' .
       'failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST233:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $array = [];
addArrayOption(GETOPTKEY => 'a=s',
               GETOPTVAL => $array);
my $array2d = [];
add2DArrayOption(GETOPTKEY => 'a=s',
                 GETOPTVAL => $array2d);

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'addArrayOption & add2DArrayOption with duplicate flags & failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST234:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $iid = addInfileOption(GETOPTKEY => 'i=s');
my $fid1 = addOutfileSuffixOption(GETOPTKEY  => 'verbose',
                                  FILETYPEID => $iid);

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'addOutfileSuffixOption matching verbose flag with failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST235:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $array = [];
addOutdirOption(GETOPTKEY => 'verbose=s');

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'addOutdirOption that matches verbose with failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST236:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $array = [];
addOutfileOption(GETOPTKEY => 'of|f|of=s');

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'addOutfileOption with duplicate in opt string & failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST237:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $a = 0;
my $b = 0;
my $c = 0;
addOptions({'a=s'  => \$a,
            'b=s'  => \$b,
            'c|a!' => \$c});

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'addOptions with duplicate in the hash & failure',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       1,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST238:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '161';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
addOutfileSuffixOption(GETOPTKEY  => 'o=s',
                       FILETYPEID => $fid);

processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'addOutfileSuffixOption that matches -o with warning & success',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST239:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '188';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
my $suff = '';
addOutfileSuffixOption(GETOPTKEY  => 'o=s',
                       FILETYPEID => $fid,
                       GETOPTVAL  => \$suff);

processCommandLine();
print STDOUT "$suff\n";
EOT

test6f($test_num,
       $sub_test_num,
       'provide getoptval to return user-supplied suffix',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' -o .suff",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       ".suff\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST240:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '190';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
print STDOUT ("FORCED: ",isForced(),"\n");
EOT

test6f($test_num,
       $sub_test_num,
       'isForced',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --force --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "FORCED: 1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST241:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '193';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
print STDOUT ("HEADER: ",headerRequested(),"\n");
EOT

test6f($test_num,
       $sub_test_num,
       'headerRequested',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --no-header",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "HEADER: 0\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST242:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '191';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
print STDOUT ("DRYRUN: ",isDryRun(),"\n");
EOT

test6f($test_num,
       $sub_test_num,
       'isDryRun false',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --no-header",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "DRYRUN: 0\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST243:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '191';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
print STDOUT ("DRYRUN: ",isDryRun(),"\n");
EOT

test6f($test_num,
       $sub_test_num,
       'isDryRun true',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --no-header --dry-run",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "DRYRUN: 1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST244:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '194';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
setDefaults(HEADER => 0);
processCommandLine();
print STDOUT ("HEADER: ",headerRequested(),"\n");
EOT

test6f($test_num,
       $sub_test_num,
       'setDefaults header',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "HEADER: 0\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST245:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '194';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption('i=s');
processCommandLine();
setDefaults(HEADER => 1);
print STDOUT ("HEADER: ",headerRequested(),"\n");
EOT

test6f($test_num,
       $sub_test_num,
       'setDefaults noheader',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "-i '$testf' --noheader",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "HEADER: 1\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST246:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '195';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY   => 'nomatchin=s',
                           DETAIL_DESC => 'Testing');
addOutfileSuffixOption(GETOPTKEY   => 'nomatchoutsuffix=s',
                       FILETYPEID  => $fid1,
                       DETAIL_DESC => 'Testing');
addOutfileOption(GETOPTKEY   => 'nomatchoutfile=s',
                 DETAIL_DESC => 'Testing');
addOutdirOption(GETOPTKEY   => 'nomatchdir=s',
                DETAIL_DESC => 'Testing');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Exclude default summary file description when detail defined',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'help',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'nomatch','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST247:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '195';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid1 = addInfileOption(GETOPTKEY => 'domatchin=s');
addOutfileSuffixOption(GETOPTKEY  => 'domatchsuffix=s',
                       FILETYPEID => $fid1);
addOutfileOption(GETOPTKEY => 'nomatchoutfile=s');
addOutdirOption(GETOPTKEY => 'nomatchdir=s');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Include default summary file description when in detail undefined',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "domatchin",undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST248:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '195';

test6f($test_num,
       $sub_test_num,
       'Include default summary suffix description when detail undefined',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'domatchsuffix',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST249:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '195';

test6f($test_num,
       $sub_test_num,
       'Exclude default summary optional outfile description always',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'nomatchoutfile','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST250:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '195';

test6f($test_num,
       $sub_test_num,
       'Exclude default summary optional outdir description always',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'nomatchdir','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST251:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '200';

$in_script = createTestScript3();
$code = << 'EOT';
processCommandLine();
print STDOUT ("DEBUG: ",isDebug(),"\n");
EOT

test6f($test_num,
       $sub_test_num,
       'isDebug',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       $testf,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "--debug 2 -i '$testf'",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       "DEBUG: 2\n",undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST252:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '197';

$in_script = createTestScript3();
$code = << 'EOT';
my $val = 0;
addOption(GETOPTKEY   => 'domatch=s',
          GETOPTVAL   => \$val,
          REQUIRED    => 1,
          DETAIL_DESC => 'Testing.');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Always include summary usage when required - addOption',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'domatch',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST253:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '197';

$in_script = createTestScript3();
$code = << 'EOT';
addInfileOption(GETOPTKEY   => 'domatch=s',
                REQUIRED    => 1,
                DETAIL_DESC => 'Testing.');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Always include summary usage when required - addInfileOption',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'domatch',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST254:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '197';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption(GETOPTKEY   => 'i=s',
                          REQUIRED    => 0);
addOutfileSuffixOption(GETOPTKEY   => 'domatch=s',
                       FILETYPEID  => $fid,
                       REQUIRED    => 1,
                       DETAIL_DESC => 'Testing.');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Always include summary usage when required - addOutfileSuffixOption',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'domatch',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST255:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '197';

$in_script = createTestScript3();
$code = << 'EOT';
addOutfileOption(GETOPTKEY   => 'domatch=s',
                 REQUIRED    => 1,
                 DETAIL_DESC => 'Testing.');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Always include summary usage when required - addOutfileOption',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'domatch',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST256:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '197';

$in_script = createTestScript3();
$code = << 'EOT';
my $a = [];
addArrayOption(GETOPTKEY   => 'domatch=s',
               GETOPTVAL   => $a,
               REQUIRED    => 1,
               DETAIL_DESC => 'Testing.');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Always include summary usage when required - addArrayOption',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'domatch',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST257:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '197';

$in_script = createTestScript3();
$code = << 'EOT';
my $a = [];
add2DArrayOption(GETOPTKEY   => 'domatch=s',
                 GETOPTVAL   => $a,
                 REQUIRED    => 1,
                 DETAIL_DESC => 'Testing.');
processCommandLine();
EOT

test6f($test_num,
       $sub_test_num,
       'Always include summary usage when required - add2DArrayOption',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       'domatch',undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST258:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.3';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
openOut(*OUT,'$testf.out');
print("ran\n");
closeOut(*OUT);
EOT

test6f($test_num,
       $sub_test_num,
       'Default run mode, no opts = run produces outfile',
       $in_script,
       #Input files used (to use in outfile name construction & do checks)
       #Up to 6.  Supply undef if not used.
       undef,undef,undef,undef,undef,undef,
       #Output files expected (to make sure they don't pre-exist)
       #Up to 6.  Supply undef if not used.
       "$testf.out",undef,undef,undef,undef,undef,
       #Test specific code & where to put it
       $code,'##TESTSLUG01',
       #Options to supply to the test script on command line in a single string
       "",
       #Exact expected whole string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,"ran\n",undef,undef,undef,undef,undef,
       #Patterns expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,undef,undef,undef,undef,undef,undef,undef,
       #Patterns not expected in string output for stdout, stderr, o1, o2, ...
       #Up to 8 (inc. STD's).  Supply undef if no test.
       undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
       #Exit code (0 = success, 1 = error, 1 means any non-0 value is expected)
       0,
       #Requirement number being tested
       $reqnum);

exit(0) if($test_num == $ending_test);


TEST259:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.3';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
openOut(*OUT,'$testf.out');
print("ran\n");
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	'Default dry-run mode, no opts = no outfile & out goes to STDOUT',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	"$testf.out",undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST260:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.4';

$in_script = createTestScript3();
#Def usage mode is implied by presence of --run, --dry-run, --help and absense
#of --usage when code does nothing (i.e. no other opts)
$code = << "EOT";
EOT

test6f2($test_num,
	$sub_test_num,
	'Default dry-run mode is usage',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--run','--help','--dry-run'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST261:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DEFAULT     => '$testf',
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist hard-coded reqd default = optional',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--run --no-header",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST262:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist usage if required & not supplied',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--help\s+OPTIONAL',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST263:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DEFAULT     => '$testf',
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist reqd w/ default = optional --run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST264:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist --run usage if reqd & not supplied',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--help\s+OPTIONAL',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST265:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DEFAULT     => '$testf',
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist reqd w/ default help-mode',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'WHAT IS THIS',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST266:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DEFAULT     => '$testf',
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist reqd w/ default help-mode --usage',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--usage",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'WHAT IS THIS','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST267:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DEFAULT     => '$testf',
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist reqd w/ default defmode:help no args - help',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL|^1\n$','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST268:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 0,
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist optional & no args - help',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'WHAT IS THIS',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST269:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                REQUIRED    => 1,
                DEFAULT     => '$testf',
                DETAIL_DESC => 'Testing.');
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist reqd w/ default defmode:help --verbose - run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL|WHAT IS THIS','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST270:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
addInfileOption(GETOPTKEY   => 'i=s',
                DEFAULT     => '$testf',
                DETAIL_DESC => 'Testing.');
processCommandLine();
print("1\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist optional w/ default defmode:help --verbose - run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL|WHAT IS THIS','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST271:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my \$fid = addInfileOption(GETOPTKEY => 'i=s',
                           DEFAULT   => '$testf');
addOutfileSuffixOption(GETOPTKEY   => 'o=s',
                       FILETYPEID  => \$fid,
                       DEFAULT     => '.out',
                       REQUIRED    => 1);
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN)) unless(isDryRun());
print("2\n");
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist defmode:dry-run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	"$testf.out",undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"2\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL|WHAT IS THIS|^1\n$','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST272:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(HEADER => 0);
addOutdirOption(GETOPTKEY => 'd=s',
                DEFAULT   => 'TEST272',
                REQUIRED  => 1);
addOutfileOption(GETOPTKEY => 'of=s');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist required outdir opt outfile default',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"TEST272/$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--of '$testf.out'",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST273:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $var = 'value1';
addOption(GETOPTKEY => 'm=s',
          GETOPTVAL => \$var,
          DEFAULT   => 'value2',
          REQUIRED  => 1);
processCommandLine();
print("$var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist required general opt default disp',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'value2',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST274:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $var = 'value1';
addOption(GETOPTKEY => 'm=s',
          GETOPTVAL => \$var,
          DEFAULT   => 'value2',
          REQUIRED  => 1);
processCommandLine();
print("$var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist required general opt default val',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--run",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"value1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST275:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $var = ['1','2'];
addArrayOption(GETOPTKEY => 'm=s',
               GETOPTVAL => $var,
               DEFAULT   => '1,2',
               REQUIRED  => 1);
processCommandLine();
print(join(',',@$var),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist required array opt default val',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--run",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1,2\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST276:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.5';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $var = [[1,2],[3,4]];
add2DArrayOption(GETOPTKEY => 'm=s',
                 GETOPTVAL => $var,
                 DEFAULT   => '1,2',
                 REQUIRED  => 1);
processCommandLine();
print(join(',',map {join(',',@$_)} @$var),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'doUndefaultedRequiredOptionsExist required array opt default val',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--run",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1,2,3,4\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST277:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:usage args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--run','--dry-run','--help'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST278:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help');
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:help args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended --usage",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--run','--dry-run','--usage'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--help\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST279:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:run args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended --usage",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--help','--dry-run','--usage'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--run','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST280:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run');
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:dry-run args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended --usage",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--help','--run','--usage'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--dry-run','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST281:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:usage args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--run','--dry-run','--help'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST282:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help');
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:help args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended --usage",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--run','--dry-run','--usage'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--help\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST283:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:run args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended --usage",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--help','--dry-run','--usage'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--run','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST284:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run');
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:dry-run args:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--extended --usage",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--help','--run','--usage'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--dry-run','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST285:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:usage args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST286:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help');
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:help args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST287:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:run args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST288:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run');
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:n defmode:dry-run args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST289:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:usage args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST290:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help');
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:help args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST291:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:run args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST292:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.6';

$in_script = createTestScript3();
$code = << 'EOT';
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
EOT

test6f2($test_num,
	$sub_test_num,
	'addRunModeOptions reqd:with_defaults defmode:usage args:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST293:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:2withdefs args:1opt  result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n2\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST294:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:2withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n2\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST295:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print("$var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:1withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST296:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:2withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n2\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST297:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my($var);
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print((defined($var) ? $var : 'undef'),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:1nodef    args:1opt  result:usg error:y warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'Run with .* for usage.','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'undef','WARNING\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST298:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my($secret_var);
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print((defined($secret_var) ? $secret_var : 'undef'),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:1nodef    args:1unk  result:run error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^undef\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST299:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:1unkdef   args:n     result:run error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST300:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:run reqd:1unkdef   args:1opt  result:run error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST301:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:2withdefs args:1opt  result:dry error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^1\n|^2\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST302:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:2withdefs args:1reqd result:dry error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^3\n|^2\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST303:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print("$var\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:1withdefs args:1reqd result:dry error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^3\n|^1\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST304:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:2withdefs args:1reqd result:dry error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^3\n|^2\n|^1\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST305:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my($var);
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print((defined($var) ? $var : 'undef'),"\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:1nodef    args:1opt  result:usg error:y warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'Run with .* for usage','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"^undef\n",'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST306:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my($secret_var);
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print((defined($secret_var) ? $secret_var : 'undef'),"\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:1nodef    args:1unk  result:dry error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^3\n|^undef\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST307:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:1unkdef   args:n     result:dry error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|1\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST308:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run',
            HEADER     => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:dry reqd:1unkdef   args:1opt  result:dry error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^1\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST309:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
processCommandLine();
print("ran\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:n         args:n     result:usg error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"^ran\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST310:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:2withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-w 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST311:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print("$var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:1withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST312:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:2withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-w 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST313:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my($var);
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print((defined($var) ? $var : 'undef'),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:1nodef    args:1opt  result:usg error:y warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'Run with .* for usage','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"^undef\n",'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST314:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my($secret_var);
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print((defined($secret_var) ? $secret_var : 'undef'),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:1nodef    args:1unk  result:run error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^undef\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST315:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:1unkdef   args:n     result:usg error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL','WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"^1\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST316:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:usg reqd:1unkdef   args:1opt  result:run error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST317:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:2withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-w 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST318:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my $var = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print("$var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:1withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST319:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my $var1 = 1;
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var1,
          REQUIRED  => 1);
my $var2 = 2;
addOption(GETOPTKEY => 'w=s',
          GETOPTVAL => \$var2,
          REQUIRED  => 1);
processCommandLine();
print("$var1\n$var2\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:2withdefs args:1reqd result:run error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-w 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST320:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my($var);
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print((defined($var) ? $var : 'undef'),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:1nodef    args:n     result:hlp error:n warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"WHAT IS THIS",undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^undef\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST321:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my($var);
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
print((defined($var) ? $var : 'undef'),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:1nodef    args:1opt  result:usg error:y warning:n',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'Run with .* for usage','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"^undef\n",'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST322:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my($secret_var);
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print((defined($secret_var) ? $secret_var : 'undef'),"\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:1nodef    args:1unk  result:run error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-v 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"3\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^undef\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST323:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:1unkdef   args:n     result:hlp error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'WHAT IS THIS','WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"--(usage|run|dry-run|help)\\s+OPTIONAL|^1\n",'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST324:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.7';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help',
            HEADER     => 0);
my $secret_var = 1;
my $var = sub {$secret_var = $_[1]};
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => $var,
          REQUIRED  => 1);
processCommandLine();
print("$secret_var\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'mode:hlp reqd:1unkdef   args:1opt  result:run error:n warning:y',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--(usage|run|dry-run|help)\s+OPTIONAL','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST325:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.13';

$in_script = createTestScript3();
$code = << 'EOT';
processCommandLine();
print("ran\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'Fatal error is --run and --dry-run supplied',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--run --dry-run",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'Run with .* for usage','ERROR\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST326:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.15';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFSDIR => '$testdefdir');
processCommandLine();
print("ran\n");
EOT

test6f2($test_num,
	$sub_test_num,
	'Disallow --version --save-as-default',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--version --save-as-default",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST327:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.16';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFSDIR => '$testdefdir',
            HEADER  => 0);
processCommandLine();
print("ran\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: save run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testdefdir/$in_script.test$test_num.$sub_test_num.pl",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--run --save-as-default",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,'--run',undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'New user defaults',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST328:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.16';

#Use the same test script with the saved user default
#$in_script = createTestScript3();
#$code = << "EOT";
#setDefaults(DEFSDIR => '$testdefdir');
#processCommandLine();
#print("ran\n") unless(isDryRun());
#EOT

#Create the defaults file
`echo "--run" > $testdefdir/$in_script.test$test_num.$sub_test_num.pl`;

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: test run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST329:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.16';

#Use the same test script with the saved user default
#$in_script = createTestScript3();
#$code = << "EOT";
#setDefaults(DEFSDIR => '$testdefdir');
#processCommandLine();
#print("ran\n") unless(isDryRun());
#EOT

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: save dry-run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testdefdir/$in_script.test$test_num.$sub_test_num.pl",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--dry-run --save-as-default",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,'--dry-run',undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST330:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.16';

#Use the same test script with the saved user default
#$in_script = createTestScript3();
#$code = << "EOT";
#setDefaults(DEFSDIR => '$testdefdir');
#processCommandLine();
#print("ran\n") unless(isDryRun());
#EOT

#Create the defaults file
`echo "--dry-run" > $testdefdir/$in_script.test$test_num.$sub_test_num.pl`;

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: test dry-run',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n|--extended",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST331:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.16';

#Use the same test script with the saved user default
#$in_script = createTestScript3();
#$code = << "EOT";
#setDefaults(DEFSDIR => '$testdefdir');
#processCommandLine();
#print("ran\n") unless(isDryRun());
#EOT

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: save help',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testdefdir/$in_script.test$test_num.$sub_test_num.pl",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--help --save-as-default",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,'--help',undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST332:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.16';

#Use the same test script with the saved user default
#$in_script = createTestScript3();
#$code = << "EOT";
#setDefaults(DEFSDIR => '$testdefdir');
#processCommandLine();
#print("ran\n") unless(isDryRun());
#EOT

#Create the defaults file
`echo "--help" > $testdefdir/$in_script.test$test_num.$sub_test_num.pl`;

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: test help',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'WHAT IS THIS',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST333:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.16';

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            DEFSDIR    => '$testdefdir');
processCommandLine();
print("ran\n") unless(isDryRun());
EOT

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: save usage',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testdefdir/$in_script.test$test_num.$sub_test_num.pl",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--usage --save-as-default",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,'--usage',undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST334:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.16';

#Use the same test script with the saved user default
#$in_script = createTestScript3();
#$code = << "EOT";
#setDefaults(DEFSDIR => '$testdefdir');
#processCommandLine();
#print("ran\n") unless(isDryRun());
#EOT

#Create the defaults file
`echo "--usage" > $testdefdir/$in_script.test$test_num.$sub_test_num.pl`;

test6f2($test_num,
	$sub_test_num,
	'Allow user to save a default run mode: test usage',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['--extended\s+OPTIONAL','Current user defaults: \[--usage\]\.'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"ran\n",'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST335:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.21';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help');
my($var);
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1);
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'--usage note in help when run mode not usage',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['Supply --usage','WHAT IS THIS'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST336:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.21';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'--usage note in help when no required options',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--help",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['Supply --usage','WHAT IS THIS'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST337:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.21';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'usage');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'--usage note in help when no required options',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--help",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['Supply --usage','WHAT IS THIS'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST338:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.21';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'--usage note in help when no required options',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--help",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	['Supply --usage','WHAT IS THIS'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST339:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.22';

$in_script = createTestScript3();
$code = << 'EOT';
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Hidden run mode options work without error: --usage hidden & works',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--usage --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--usage\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST340:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.22';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Hidden run mode options work without error: --help hidden',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--usage --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--help\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST341:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.22';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'help');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Hidden run mode options work without error: --help works',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--help",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'WHAT IS THIS',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST342:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.22';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Hidden run mode options work without error: --run hidden',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--usage --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--run\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST343:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.22';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Hidden run mode options work without error: --run works',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--run",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL|WHAT IS THIS','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST344:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.22';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Hidden run mode options work without error: --dry-run hidden',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--usage --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--dry-run\s+OPTIONAL','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST345:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.22';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'dry-run');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Hidden run mode options work without error: --dry-run works',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--dry-run",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'--extended\s+OPTIONAL|WHAT IS THIS','(ERROR|WARNING)\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST346:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '157.23';

$in_script = createTestScript3();
$code = << 'EOT';
my($var);
addOption(GETOPTKEY => 'v=s',
          GETOPTVAL => \$var,
          REQUIRED  => 1,
          HIDDEN    => 1);
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Prevent required options w/o defaults from being hidden - addOpt',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST347:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.23';

$in_script = createTestScript3();
$code = << 'EOT';
addOutfileOption(GETOPTKEY => 'of=s',
                 REQUIRED  => 1,
                 HIDDEN    => 1);
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Prevent required options w/o defaults from being hidden - addOutfOpt',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST348:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.23';

$in_script = createTestScript3();
$code = << 'EOT';
my $fid = addInfileOption(GETOPTKEY => 'i=s');
addOutfileSuffixOption(GETOPTKEY  => 'o=s',
                       FILETYPEID => $fid,
                       REQUIRED   => 1,
                       HIDDEN     => 1);
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Prevent required options w/o defaults from being hidden - addSuffOpt',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST349:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.23';

$in_script = createTestScript3();
$code = << 'EOT';
my $var = [];
addArrayOption(GETOPTKEY => 'a=s',
               GETOPTVAL => $var,
               REQUIRED  => 1,
               HIDDEN    => 1);
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Prevent required options w/o defaults from being hidden - AddArrOpt',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST350:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.23';

$in_script = createTestScript3();
$code = << 'EOT';
my $var = [];
add2DArrayOption(GETOPTKEY => 'a=s',
                 GETOPTVAL => $var,
                 REQUIRED  => 1,
                 HIDDEN    => 1);
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Prevent required options w/o defaults from being hidden - Add2DArOpt',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST351:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '157.23';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'invalid');
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	'Invalid default run mode causes fatal error',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST352:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
warning("Test warning");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report does not include trace in warning when debug = false',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 WARNING LIKE: \\[WARNING1: Test warning",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"ERROR\\d|1 WARNING LIKE: \\[WARNING1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST353:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
error("Test error");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report does not include trace in error when debug = false',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 ERROR LIKE: \\[ERROR1: Test error",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"WARNING\\d|1 ERROR LIKE: \\[ERROR1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST354:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
warning("Test warning");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report does not include trace in warning even when debug = undef',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 WARNING LIKE: \\[WARNING1: Test warning",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"ERROR\\d|1 WARNING LIKE: \\[WARNING1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST355:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
error("Test error");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report does not include trace in error even when debug = undef',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 ERROR LIKE: \\[ERROR1: Test error",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"WARNING\\d|1 ERROR LIKE: \\[ERROR1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST356:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
warning("Test warning");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report includes trace in warning when debug = true',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 WARNING LIKE: \\[WARNING1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"ERROR\\d|1 WARNING LIKE: \\[WARNING1: Test warning",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST357:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
error("Test error");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report includes trace in error when debug = true',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 ERROR LIKE: \\[ERROR1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"WARNING\\d|1 ERROR LIKE: \\[ERROR1: Test error",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST358:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
warning("Test warning");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report includes trace in warning even when debug = undef',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 WARNING LIKE: \\[WARNING1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"ERROR\\d|1 WARNING LIKE: \\[WARNING1: Test warning",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST359:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '198';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
error("Test error");
EOT

test6f2($test_num,
	$sub_test_num,
	'Run report includes trace in error even when debug = undef',
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 ERROR LIKE: \\[ERROR1:.*MAIN",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"WARNING\\d|1 ERROR LIKE: \\[ERROR1: Test error",undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);



TEST360:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '223';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
error("Test error");
EOT

test6f2($test_num,
	$sub_test_num,
	"Only print report if command line processed w/o crit. error & " .
	"programmer's code runs - true",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'Done\.\s+STATUS:',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST361:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '223';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'usage');
processCommandLine();
error("Test error");
EOT

test6f2($test_num,
	$sub_test_num,
	"Only print report if command line processed w/o crit. error & " .
	"programmer's code runs - usage/no-run",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        'Done\.\s+STATUS:',undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST362:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '223';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
error("Test error");
EOT

test6f2($test_num,
	$sub_test_num,
	"Only print report if command line processed w/o crit. error & " .
	"programmer's code runs - crit. error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--bad",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        'Done\.\s+STATUS:',undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST363:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '235';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
error("Test error");
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
my $scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Run report errors/warnings include scriptname in pipeline mode - error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--pipeline-mode",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 ERROR LIKE: \\\[ERROR1:$scrpat:",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST364:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '235';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
error("Test error");
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Run report errors/warnings include scriptname in pipeline mode - debug/error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--pipeline-mode --debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 ERROR LIKE: \\\[ERROR1:$scrpat:",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST365:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '235';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
warning("Test warning");
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Run report errors/warnings include scriptname in pipeline mode - warning",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--pipeline-mode",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 WARNING LIKE: \\\[WARNING1:$scrpat:",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST366:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '235';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
warning("Test warning");
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Run report errors/warnings include scriptname in pipeline mode - debug/error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--pipeline-mode --debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,"1 WARNING LIKE: \\\[WARNING1:$scrpat:",undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST367:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '184';

$in_script = createTestScript3();
$code = << 'EOT';
error("Test error");
warning("Test warning");
debug("Test debug");
processCommandLine();
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Errors/warnings/debugs include scriptname when flushing stderr in pipeline mode - debug/error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--pipeline-mode --debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,["WARNING1:$scrpat:","ERROR1:$scrpat:","DEBUG1:$scrpat:"],undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST368:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '177';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
my $id = addInfileOption(GETOPTKEY => 'i=');
addOutfileOption(GETOPTKEY => 'ou=');
my $a = [];
addArrayOption(GETOPTKEY => 'a=s@',
               GETOPTVAL => $a);
my $a2 = [];
add2DArrayOption(GETOPTKEY => 'a2=i',
                 GETOPTVAL => $a2);
addOutfileSuffixOption(GETOPTKEY => 's=i',
                       FILETYPEID => $id);
addOutdirOption(GETOPTKEY => 'd=');
processCommandLine();
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Validate GETOPTKEY to string options",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,["Invalid option flag definition: .i=","Invalid option flag definition: .ou=","The option specification: .a=s\\\@","a2=i. was passed in","Invalid GetOpt parameter flag definition: .s=i","Invalid GetOpt parameter flag definition: .d="],undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST369:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '242';

$in_script = createTestScript3();
$code = << 'EOT';
addInfileOption(GETOPTSTR => 'i=s');
EOT

test6f2($test_num,
	$sub_test_num,
	"Invalid hash key - all invalid - warning",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING1: No matching matching keys',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST370:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '242';

$in_script = createTestScript3();
$code = << 'EOT';
addInfileOption(GETOPTKEY => 'i=s',
                BAD_KEY   => 'Test description');
EOT

test6f2($test_num,
	$sub_test_num,
	"Invalid hash key - some invalid - error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR1: Unrecognized hash key',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);



TEST371:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '100';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
openIn(*IN,'bad_file');
debug("Test debug");
error("Test error");
warning('Test warning');
EOT

test6f2($test_num,
	$sub_test_num,
	"Support for modules in traces - full",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--debug --debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,['DEBUG1:MAIN\(LINE\d+\):Test debug','ERROR1:CommandLineInterface\.pm\/','ERROR2:MAIN\(LINE\d+\):','WARNING1:MAIN\(LINE\d+\):'],undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST372:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '100';

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
openIn(*IN,'bad_file');
debug("Test debug");
error("Test error");
warning('Test warning');
EOT

test6f2($test_num,
	$sub_test_num,
	"Support for modules in traces - short",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,['DEBUG1:MAIN\(LINE\d+\):Test debug','ERROR1:CommandLineInterface\.pm\/','ERROR2:MAIN\(LINE\d+\):','WARNING1:MAIN\(LINE\d+\):'],undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,undef,undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST373:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '103&252';

$in_script = createTestScript3();
$code = << 'EOT';
setScriptInfo(VERSION => '1.0');
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Version flag works - simple",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--version",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1.0\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        "$scrpat|Last Modified|CommandLineInterface\\.pm",'ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST374:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '103&252';

$in_script = createTestScript3();
$code = << 'EOT';
setScriptInfo(VERSION => '1.0');
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;

test6f2($test_num,
	$sub_test_num,
	"Version flag works - with script name",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--version --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"$out_script Version 1.0\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        'Last modified|CommandLineInterface\.pm','ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST375:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '103&252';

$in_script = createTestScript3();
$code = << 'EOT';
setScriptInfo(VERSION => '1.0');
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Version flag works - with extra script info",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--version --extended --extended",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	[$scrpat,'1\.0','Last modified'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        'CommandLineInterface\.pm','ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST376:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '103&252';

$in_script = createTestScript3();
$code = << 'EOT';
setScriptInfo(VERSION => '1.0');
EOT

$out_script = "$in_script.test$test_num.$sub_test_num.pl";
$out_script =~s/.*\///;
$scrpat = quotemeta($out_script);

test6f2($test_num,
	$sub_test_num,
	"Version flag works - with CLI info",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--version --extended 3",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	[$scrpat,'1\.0','Last modified','CommandLineInterface\.pm'],undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum);

exit(0) if($test_num == $ending_test);


TEST377:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '261';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
openOut(*OUT,'$testf.out');
print OUT "2\\n";
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	"Append flag - global file",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--append",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n2\n",undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	1);

exit(0) if($test_num == $ending_test);


TEST378:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '261';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $fid = addInfileOption('i=s');
addOutfileSuffixOption(GETOPTKEY  => 'o=s',
                       FILETYPEID => $fid);
openOut(*OUT,getOutfile());
print OUT "2\n";
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	"Append flag - outfile suffix",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-i $testf -o .out --append",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n2\n",undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	1);

exit(0) if($test_num == $ending_test);


TEST379:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '261';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $fid = addOutfileOption(GETOPTKEY  => 'of=s');
openOut(*OUT,getOutfile($fid));
print OUT "2\n";
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	"Append flag - outfile",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--of $testf.out --append",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n2\n",undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	1);

exit(0) if($test_num == $ending_test);


TEST380:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '261';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $fid = addOutfileOption(GETOPTKEY     => 'of=s',
                           COLLISIONMODE => 'error');
openOut(*OUT,getOutfile($fid));
print OUT "2\n";
closeOut(*OUT);
openOut(*OUT,getOutfile($fid));
print OUT "3\n";
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	"Append flag - non-merge collision mode still works, config error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--of $testf.out --of $testf.out --append",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n",undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d+: Output file name conflict',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	1);

exit(0) if($test_num == $ending_test);


TEST381:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '261';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $fid = addOutfileOption(GETOPTKEY     => 'of=s',
                           COLLISIONMODE => 'merge');
openOut(*OUT,getOutfile($fid));
print OUT "2\n";
closeOut(*OUT);
openOut(*OUT,getOutfile($fid));
print OUT "3\n";
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	"Append flag - non-merge collision mode still works, config merge",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--of $testf.out --of $testf.out --append",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n2\n3\n",undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'ERROR|WARNING|DEBUG',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	1);

exit(0) if($test_num == $ending_test);


TEST382:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '261';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $fid = addOutfileOption(GETOPTKEY     => 'of=s',
                           COLLISIONMODE => 'error');
openOut(*OUT,getOutfile($fid));
print OUT "2\n";
closeOut(*OUT);
openOut(*OUT,getOutfile($fid));
print OUT "3\n";
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	"Append flag - non-merge collision mode still works, user merge",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--of $testf.out --of $testf.out --append --collision-mode merge",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n2\n3\n",undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(ERROR|WARNING|DEBUG)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	1);

exit(0) if($test_num == $ending_test);


TEST383:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '261';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
my $fid = addOutfileOption(GETOPTKEY     => 'of=s',
                           COLLISIONMODE => 'merge');
openOut(*OUT,getOutfile($fid));
print OUT "2\n";
closeOut(*OUT);
openOut(*OUT,getOutfile($fid));
print OUT "3\n";
closeOut(*OUT);
EOT

test6f2($test_num,
	$sub_test_num,
	"Append flag - non-merge collision mode still works, user error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--of $testf.out --of $testf.out --append --collision-mode error",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n",undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d+: Output file name conflict',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(WARNING|DEBUG)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	1);

exit(0) if($test_num == $ending_test);


TEST384:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '271';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
while(nextFileCombo())
  {
    openIn(*IN,getInfile());
    openOut(*OUT,getOutfile());

    while(getLine(*IN))
      {print}

    closeOut(*OUT);
    closeIn(*IN);
  }
EOT

test6f2($test_num,
	$sub_test_num,
	"suffix and outfile options output to same file - --outfile",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-i $testf --outfile $testf.out",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n",undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(ERROR|WARNING|DEBUG)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST385:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '271';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
while(nextFileCombo())
  {
    openIn(*IN,getInfile());
    openOut(*OUT,getOutfile());

    while(getLine(*IN))
      {print}

    closeOut(*OUT);
    closeIn(*IN);
  }
EOT

test6f2($test_num,
	$sub_test_num,
	"suffix and outfile options output to same file - -o",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out",undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-i $testf -o .out",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,"1\n",undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(ERROR|WARNING|DEBUG)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST386:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '271';

`echo 1 > $testf.out`;

$in_script = createTestScript3();
$code = << 'EOT';
setDefaults(HEADER => 0);
while(nextFileCombo())
  {
    openIn(*IN,getInfile());
    openOut(*OUT,getOutfile());

    while(getLine(*IN))
      {print}

    closeOut(*OUT);
    closeIn(*IN);
  }
EOT

test6f2($test_num,
	$sub_test_num,
	"suffix and outfile options output to same file - both = error",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	"$testf.out","$testf.out2",undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"-i $testf -o .out --outfile $testf.out2",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	"$testf.out","$testf.out2",undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'ERROR\d+: Cannot supply both an outfile suffix',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(WARNING|DEBUG)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST387:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '269';

$in_script = createTestScript3();
$code = << 'EOT';
EOT

test6f2($test_num,
	$sub_test_num,
	"No SIG_WARN '__ANON__' in trace for runtime warnings",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--bad-opt --debug",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d+:Long.pm.FindOption',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(WARNING|ERROR)([2-9]|\d\d+):',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST388:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '254';

$in_script = createTestScript4();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
print($undeclared_variable);
EOT

test6f2($test_num,
	$sub_test_num,
	"Don't continue when compile error & use entire runtime warning message - undeclared var during strict",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'',undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'CommandLineInterface: Unable to complete set up\.',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(DEBUG|WARNING|ERROR)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST389:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '254';

$in_script = createTestScript4();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run');
processCommandLine();
my($undefined_variable);
print($undefined_variable);
EOT

test6f2($test_num,
	$sub_test_num,
	"Don't continue when compile error & use entire runtime warning message - undefined var used",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,['WARNING\d+:','Runtime warning','undefined_variable'],undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(DEBUG|ERROR)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST390:

#Describe the test
$test_num++;
$sub_test_num = 1;
$reqnum = '253';

$in_script = createTestScript4();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY => 'i=s',
                HIDDEN    => 1,
                PRIMARY   => 1,
                DEFAULT   => '$testf',
                REQUIRED  => 1);
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	"addInfileOption hidden parameter - requirements met (all)",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(DEBUG|ERROR|WARNING)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST391:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '253';

$in_script = createTestScript4();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY => 'i=s',
                HIDDEN    => 1,
                PRIMARY   => 0,
                DEFAULT   => '$testf',
                REQUIRED  => 1);
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	"addInfileOption hidden parameter - requirements met (default)",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(DEBUG|ERROR|WARNING)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST392:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '253';

$in_script = createTestScript4();
$code = << 'EOT';
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY => 'i=s',
                HIDDEN    => 1,
                PRIMARY   => 0,
                DEFAULT   => undef,
                REQUIRED  => 0);
processCommandLine();
while(nextFileCombo())
  {
    my $inf = getInfile() || next;
    openIn(*IN,$inf);
    print(getLine(*IN));
    closeIn(*IN);
  }
EOT

test6f2($test_num,
	$sub_test_num,
	"addInfileOption hidden parameter - requirements met (not required:no output)",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        '.','(DEBUG|ERROR|WARNING)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0);

exit(0) if($test_num == $ending_test);


TEST393:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '253';

$in_script = createTestScript4();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY => 'i=s',
                HIDDEN    => 1,
                PRIMARY   => 1,
                DEFAULT   => undef,
                REQUIRED  => 1);
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	"addInfileOption hidden parameter - requirements met (primary/stdin)",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	"1\n",undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(DEBUG|ERROR|WARNING)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0,
	#Provide the first file on stdin
	1);

exit(0) if($test_num == $ending_test);


TEST394:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '253';

$in_script = createTestScript4();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY => 'i=s',
                HIDDEN    => 1,
                PRIMARY   => 1,
                DEFAULT   => undef,
                REQUIRED  => 1);
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	"addInfileOption hidden parameter - requirements met (primary/no-stdin:error & usage)",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"--verbose",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	' < input_file','ERROR\d+:',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(DEBUG|WARNING)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	1,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0,
	#Provide the first file on stdin
	0);

exit(0) if($test_num == $ending_test);


TEST395:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '253';

$in_script = createTestScript4();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'run',
            HEADER     => 0);
addInfileOption(GETOPTKEY => 'i=s',
                HIDDEN    => 1,
                PRIMARY   => 0,
                DEFAULT   => undef,
                REQUIRED  => 1);
processCommandLine();
openIn(*IN,getInfile());
print(getLine(*IN));
closeIn(*IN);
EOT

test6f2($test_num,
	$sub_test_num,
	"addInfileOption hidden parameter - requirements invalid:warning & unhide",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	$testf,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,'WARNING\d+: Cannot hide',undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(DEBUG|ERROR)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0,
	#Provide the first file on stdin
	0);

exit(0) if($test_num == $ending_test);


TEST396:

#Describe the test
$test_num++;
$sub_test_num++;
$reqnum = '253';

$in_script = createTestScript4();
$code = << "EOT";
setDefaults(DEFRUNMODE => 'help');
addInfileOption(GETOPTKEY => 'uniq-flag=s',
                HIDDEN    => 1,
                PRIMARY   => 1);
processCommandLine();
EOT

test6f2($test_num,
	$sub_test_num,
	"addInfileOption hidden primary parameter - help includes STDIN and no flag",
	$in_script,
	#Input files used (to use in outfile name construction & do checks)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Output files to test (to make sure they don't pre-exist)
	#Up to 6.  Supply undef if not used.
	undef,undef,undef,undef,undef,undef,
	#Test specific code & where to put it
	$code,'##TESTSLUG01',
	#Options to supply to the test script on command line in 1 string
	"",
	#Names of files expected to NOT be created. Supply to Outfiles to test^
	#Up to 6 (NOT inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,
	#Exact expected whole string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	undef,undef,undef,undef,undef,undef,undef,undef,
	#Patterns expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
	'\* STDIN FORMAT:',undef,undef,undef,undef,undef,undef,undef,
	#Patterns not expected in string output for stdout, stderr, o1, o2, ...
	#Up to 8 (inc. STD's).  Supply undef if no test.
        undef,'(ERROR|DEBUG|WARNING)\d+:',undef,undef,undef,undef,undef,undef,
	#Exit code (0 = success, 1 = error: means any non-0 value is expected)
	0,
	#Requirement number being tested
	$reqnum,
	#1 = Do not delete the first outfile if it pre-exists
	0,
	#Provide the first file on stdin
	0);

exit(0) if($test_num == $ending_test);


