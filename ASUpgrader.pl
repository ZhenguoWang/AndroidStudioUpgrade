#!/usr/bin/perl -w

# Install command:
# java -classpath AI-130.745757-132.809981-patch-win.jar com.intellij.updater.Runner install .  
use strict; # As always.
use Getopt::Std;

use Data::Dumper;
use LWP::Simple;
use XML::Simple; 
use Win32::Registry;


use constant UPDATE_XML_FILE=>'updates.xml';
use constant UPDATE_XML_URL=>'https://dl.google.com/android/studio/patches/'.UPDATE_XML_FILE;
use constant LOCAL_TMP_PATH=>'.';
use constant LOCAL_UPDATE_XML_PATH=>LOCAL_TMP_PATH.'/'.UPDATE_XML_FILE;
use constant LOCAL_UPDATE_FILE_PATH=>LOCAL_TMP_PATH.'/';
use constant PATCH_FILE_LOCATION=>'https://dl.google.com/android/studio/patches/';
use constant PATCH_FILE_NAME_WIN_EXT=>'-patch-win.jar';
use constant INSTALL_COMMAND_PART1=>'java -classpath ';
use constant INSTALL_COMMAND_PART3=>' com.intellij.updater.Runner install ';
use constant DEFAULT_PATCH_VERSION=>'release';


sub println {
	foreach ( @_ ) {
		print $_;
	}
	
	print "\n";
}

sub executeCmd {
	my ($cmd) = @_;
	println "Cmd: $cmd";
	
	my $output = qx($cmd);
	#println "result: $output";
	
	return $output;
} 


sub removeLineWrap {
	my ($msg) = @_;
	$msg =~ s/\n//g;
	return $msg;
}

sub getReleaseType {
	if (scalar(@ARGV) == 1) {
		return $ARGV[0];
	} 
	
	return DEFAULT_PATCH_VERSION;
}

sub downloadASUpdateXML {
	return downloadFile(UPDATE_XML_URL, LOCAL_UPDATE_XML_PATH);
}

sub saveFile {
	my ($saveTo, $content) = @_;

	my $FILE;
	open ($FILE, ">$saveTo") or die ("Can't create $saveTo");
	print $FILE $content;
	close($FILE);
}


sub downloadFile {
	my ($url, $saveAsPath) = @_;
	print "Downloading $url ...";
	my $FILE;
	open ($FILE, ">$saveAsPath") or die ("Can't create $saveAsPath");
	binmode($FILE);
	
	my $ua = LWP::UserAgent->new();
	$ua->timeout(10);
	
	my $res = $ua->get( $url, 
		':content_cb' => sub {
        my ( $chunk, $res, $proto ) = @_;
        eval {
			print ".";
           # local $SIG{ALRM} = sub { die "time out\n" };
            #alarm 2;
           # println "res: $res, proto: $proto, length: length($chunk)";
		  # println $FILE, "in callback";
		  
			print $FILE $chunk;
           # alarm 0;
        }});
	
	close $FILE;
	#println "code: ", $res->code(), " message:", $res->message();
	
	my $result = -1;
	if (!$res->is_error()) {
		println "Done";
		println "Saved to file $saveAsPath";
		$result = 0;
		
	} else {
		println "Failed";
	}
	
	return $result;
	#saveFile($saveAsPath, $content);
}
 
sub getASInstallHome {
	my $key = 'SOFTWARE\Android Studio';
	my $value;
	my $objs ;
	my $type;
	$::HKEY_LOCAL_MACHINE->Open($key, $objs);
	$objs->QueryValueEx("Path", $type, $value);
	$objs->Close();

	$::HKEY_LOCAL_MACHINE->Close();
	return $value;
}
 
my $asInstHome = getASInstallHome();
 
sub getASCurrentBuildString {
	
	println "asInstHome: $asInstHome";
	
	
	my $asCurBuildFilePath = $asInstHome.'\build.txt';
	open(BUILD_FILE, $asCurBuildFilePath) or die "Can't open $asCurBuildFilePath";
	my $buildString = <BUILD_FILE>;
	close(BUILD_FILE);
	
	return $buildString;
}

sub getPatchFileName {
	my ($currBuildString, $newBuildNumber) = @_;
	return $currBuildString."-".$newBuildNumber.PATCH_FILE_NAME_WIN_EXT;
}

sub makePatchFileURL {
	my ($currBuildString, $latestBuildNumber) = @_;
	return PATCH_FILE_LOCATION.getPatchFileName($currBuildString, $latestBuildNumber);
}

sub makeLocalPatchFileURL {
	my ($currBuildString, $latestBuildNumber) = @_;
	return LOCAL_UPDATE_FILE_PATH.getPatchFileName($currBuildString, $latestBuildNumber);
}

sub makeTmpDir {
	my ($currBuildString, $latestBuildNumber) = @_;
	my $tmpDir = $currBuildString."-".$latestBuildNumber;
	executeCmd("mkdir $tmpDir ");
	return $tmpDir;
}

sub downloadUpdatePatch {
	my ($currBuildString, $latestBuildNumber) = @_;
	
	my $patchFileURL = makePatchFileURL($currBuildString, $latestBuildNumber);
	#println "PatchFileURL: $patchFileURL";
	my $localPatchFileURL = makeLocalPatchFileURL($currBuildString, $latestBuildNumber);
	return downloadFile($patchFileURL, $localPatchFileURL);
}

sub isASRunning {
	
	return 0;
}

sub preparePatchFile {
	my ($localPathUrl, $currBuildString, $latestBuildNumber) = @_;
	my $tmpDir = makeTmpDir($currBuildString, $latestBuildNumber);
	my $patchFileName = getPatchFileName($currBuildString, $latestBuildNumber);
	executeCmd("move $localPathUrl $tmpDir");
	
	return $tmpDir."\\".$patchFileName;
	
}

sub setupPatch {
	my ($localPathUrl) = @_;
	

	println "asInstHome: $asInstHome";
	my $cmd = INSTALL_COMMAND_PART1.$localPathUrl.INSTALL_COMMAND_PART3."\"".$asInstHome."\"";
	executeCmd($cmd);
	
	
}

sub installPatch {
	my ($localPathUrl, $curASBuildString, $newStableASbuildNumber) = @_;
	
	my $tmpPatchFileUrl = preparePatchFile($localPathUrl, $curASBuildString, $newStableASbuildNumber);
	
	setupPatch($tmpPatchFileUrl);
}

sub getNewStableASbuildNumber {
	my ($releaseType) = @_;
	
	my $x = XMLin(LOCAL_UPDATE_XML_PATH, KeyAttr => { product => 'name' }); 

	#print Dumper $x;
	my $channels = $x->{product}{channel};
	my $code = $x->{product}{code};
	
	my $channelCount = scalar(@$channels);
	
	my $buildString;
	foreach (@$channels) {
		#print $_{status}, "\n";
		#print $_->{status}, "\t\t-\t", $_->{build}{number}, "\n";
		if ($_->{status} eq $releaseType) {
			$buildString = $_->{build}{number};
		}
	}

	return $buildString;
}

sub hasNewStableRelease {
	my ($curASBuildNumber, $newStableASbuildNumber) = @_;
		
	if ($newStableASbuildNumber > $curASBuildNumber) {		
		return 1;
	}
	
	return 0;
}

sub getASCurrentBuildNumber {
	my ($buildString) = @_;
	
	my $buildNumber="";
	
	if ($buildString =~ m/[A-Z]+\-(\d+\.\d+)/g) {
		$buildNumber = $1;
	}
	
	return $buildNumber;
}


sub test {
	executeCmd("java -classpath ./AI-135.1641136-135.1740770-patch-win.jar com.intellij.updater.Runner install .");	
}

sub forceFlushOutput {
	select (STDOUT);
	$| = 1 ;
}

sub main {

	forceFlushOutput();

	
	#test();
	#return;
	
	
	my $curASBuildString = getASCurrentBuildString();
	my $curASBuildNumber = getASCurrentBuildNumber($curASBuildString);
	
	println "Installed: $curASBuildNumber";
	
	
	if (downloadASUpdateXML() != 0) {
		return;
	}
	
	my $releaseType = getReleaseType();
	my $newStableASbuildNumber = getNewStableASbuildNumber($releaseType);
	println "Latest stable release: $newStableASbuildNumber";

		
	if (hasNewStableRelease($curASBuildNumber, $newStableASbuildNumber) == 1) {
		downloadUpdatePatch($curASBuildString, $newStableASbuildNumber);
		
		my $localPathUrl = makeLocalPatchFileURL($curASBuildString, $newStableASbuildNumber);
		installPatch($localPathUrl, $curASBuildString, $newStableASbuildNumber);
		return;
	}
	
	println("Your Android Studio is up to date!");
	
}



main();