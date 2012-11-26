#!/bin/bash                                   
#.git/hooks/post-merge
#
# Kudos: https://gist.github.com/1186990 & https://gist.github.com/1379127
#
# =====================================================================================================================
#
# *** XCODE CONFIGURATION:
#
# XCODE PROJECT DIRECTORY:
INSTALL_PATH="/Applications"
#
VERSION_TYPE='revision'
BUILD_LOG="/tmp/xcodebuild.log"
ARCHIVE_ROOT=~/Library/Developer/Xcode/Archives


# Find your API_TOKEN at: https://testflightapp.com/account/
TESTFLIGHT_API_TOKEN=YOUR_API_TOKEN
#
# Find your TEAM_TOKEN at: https://testflightapp.com/dashboard/team/edit/
TESTFLIGHT_TEAM_TOKEN=YOUR_TEAM_TOKEN
#
# Default selection of Distribution List(s), e.g. "DevTeam,Clients":
AUTO_DISTRIBUTION_LISTS=YOUR_DISTRO_LIST
## Default selection for the Notify team members dialog ("True" -> Notify team members, "False" -> Don't notify):
TESTFLIGHT_SHOULD_NOTIFY="False"
TESTFLIGHT_DISTRIBUTION_LIST="${AUTO_DISTRIBUTION_LISTS}"




# Project Settings
LOCAL_DIR=`pwd`
GIT_ROOT="${LOCAL_DIR}"
XCODE_DIR=`find . -iname *.xcodeproj -d`
XCODE_PROJECT="${LOCAL_DIR}/YOUR_XCODE_PROJECT.xcodeproj"
XCODE_TARGET="YOUR_XCODE_TARGET"
XCODE_WORKSPACE="${LOCAL_DIR}/YOUR_XCODE_WORKSPACE.xcodeproj/project.xcworkspace"
XCODE_SCHEME="YOUR_XCODE_SCHEME"
    


# DO NOT SET!
CODE_SIGN_IDENTITY=""

DSYM=""
APP=""
ARCHIVE_XCODE=""
ARCHIVE_APP=""
ARCHIVE_DSYM=""

SOURCE_ROOT=""
INFOPLIST_FILE=""
WRAPPER_NAME=""
ARCHIVE_XCODE=""
ARCHIVE_DSYM=""
ARCHIVE_APP=""
RELEASE_NOTES=""
DSYM_TARGET=""
IPA_TARGET=""


usage()
{
cat << EOF
usage: pixie_dust

Generic Xcode Builder

OPTIONS:
   -h      usage notes
   -w      Xcode Workspace [required]
   -r      Server address
   -p      Server root password
   -v      Verbose
EOF
}


run()
{
    setXcodeProjectSettings
    
    openLog
    
    setXcodeProjectSpecificVariables
    
    setCertificate
    
    setProvisioningProfile
    
    updateBuildVersion
    
    buildProject
      
    gitTagRelease
      
    gitReleaseNotes
    
    createAPP
    
    uploadTestFlight
}



function setXcodeProjectSettings()
{
    # Test Sample:
    # XCODE_PROJECT="/Volumes/PixieDust/src/PixieDust.xcodeproj"
    # XCODE_TARGET="PixieDust"
    
    settings=`xcodebuild -project $XCODE_PROJECT -target $XCODE_TARGET -showBuildSettings`
    
    SOURCE_ROOT=`echo "$settings" | grep SOURCE_ROOT | awk '{print $3}'`/
    INFOPLIST_FILE=$SOURCE_ROOT`echo "$settings" | grep INFOPLIST_FILE | awk '{print $3}'`
    WRAPPER_NAME=$SOURCE_ROOT`echo "$settings" | grep WRAPPER_NAME | awk '{print $3}'`
    
    # echo $SOURCE_ROOT
    # echo $INFOPLIST_FILE
    # echo $WRAPPER_NAME
}


function openLog()
{
    if [ "$SOURCE_ROOT" = "" ]; then
        echo "Can't open build log."
        exit 1
    fi
    
    SHOW_DEBUG_CONSOLE=${1:-"FALSE"}
    echo $SHOW_DEBUG_CONSOLE
    
    /bin/rm -f $BUILD_LOG
    echo "Starting TestFlight Upload Process" > $BUILD_LOG
    if [ "$SHOW_DEBUG_CONSOLE" = "TRUE" ]; then
        /usr/bin/open -a /Applications/Utilities/Console.app $BUILD_LOG
    fi
    
    /bin/rm -f $BUILD_LOG
    echo "*~*~* Pixie Dust *~*~*" >> $BUILD_LOG
    echo >> $BUILD_LOG
}



function setXcodeProjectSpecificVariables()
{
    # Test Sample:
    # INSTALL_PATH="/Applications"
    # XCODE_PROJECT="/Volumes/PixieDust/src/PixieDust.xcodeproj"
    # XCODE_TARGET="PixieDust"
    
    
    settingsStrings=`xcodebuild -project $XCODE_PROJECT -target $XCODE_TARGET -showBuildSettings`
    
    INFOPLIST_FILE=`echo "$settingsStrings" | grep INFOPLIST_FILE | awk -F= '{print $NF}'`
    INFOPLIST_FILE=${INFOPLIST_FILE%%}
    INFOPLIST_FILE=${INFOPLIST_FILE##}
    echo $INFOPLIST_FILE

    DWARF_DSYM_FOLDER_PATH=`echo "$settingsStrings" | grep DWARF_DSYM_FOLDER_PATH | awk -F= '{print $NF}'`
    DWARF_DSYM_FOLDER_PATH=${DWARF_DSYM_FOLDER_PATH%%}
    DWARF_DSYM_FOLDER_PATH=${DWARF_DSYM_FOLDER_PATH##}
    echo $DWARF_DSYM_FOLDER_PATH
    
    DWARF_DSYM_FILE_NAME=`echo "$settingsStrings" | grep DWARF_DSYM_FILE_NAME | awk -F= '{print $NF}'`
    DWARF_DSYM_FILE_NAME=${DWARF_DSYM_FILE_NAME%%}
    DWARF_DSYM_FILE_NAME=${DWARF_DSYM_FILE_NAME##}
    echo $DWARF_DSYM_FILE_NAME
    
    
    ARCHIVE_PRODUCTS_PATH=`echo "$settingsStrings" | grep ARCHIVE_PRODUCTS_PATH | awk -F= '{print $NF}'`
    ARCHIVE_PRODUCTS_PATH=${ARCHIVE_PRODUCTS_PATH%%}
    ARCHIVE_PRODUCTS_PATH=${ARCHIVE_PRODUCTS_PATH##}
    echo $ARCHIVE_PRODUCTS_PATH

    INSTALL_PATH=`echo "$settingsStrings" | grep INSTALL_PATH | awk -F= '{print $NF}'`
    INSTALL_PATH=${INSTALL_PATH%%}
    INSTALL_PATH=${INSTALL_PATH##}
    echo $INSTALL_PATH

    WRAPPER_NAME=`echo "$settingsStrings" | grep WRAPPER_NAME | awk -F= '{print $NF}'`
    WRAPPER_NAME=${WRAPPER_NAME%%}
    WRAPPER_NAME=${WRAPPER_NAME##}
    echo $WRAPPER_NAME
    
    DSYM="$DWARF_DSYM_FOLDER_PATH/$DWARF_DSYM_FILE_NAME"
    APP="$ARCHIVE_PRODUCTS_PATH/$INSTALL_PATH/$WRAPPER_NAME"
    
    echo $DSYM
    echo $APP
}




# sets:      CODE_SIGN_IDENTITY
function setCertificate() 
{
    # Test Sample:
    # MOBILE_PROVISIONING_PATH
    
    SAVEIFS=$IFS
    IFS=$'\n'

    pushd "${HOME}/Library/MobileDevice/Provisioning Profiles"
    SIGNING_IDS=($(security find-identity -v -p codesigning | egrep -oE '"[^"]+"'))

    FOUND_ID="FALSE"
    if [ $CODE_SIGN_IDENTITY ]; then
        for (( i=0; i < ${#SIGNING_IDS[@]}; i++ )); do
            if [ $CODE_SIGN_IDENTITY == ${SIGNING_IDS[$i]} ]; then
                FOUND_ID="TRUE"
            fi
        done    
    fi
    
    if [ $CODE_SIGN_IDENTITY == "" ]; then 
        echo "No certificate found for $CODE_SIGN_IDENTITY"
        exit 1
    fi
    
    if [ $FOUND_ID == "FALSE" ]; then 
        echo ""
        echo "No default certificate set."
        for (( i=0; i < ${#SIGNING_IDS[@]}; i++ )); do
            echo   [$i]: ${SIGNING_IDS[$i]}
        done
        
        echo "Select a certificate [default 0]: "
        read DEFAULT_ID </dev/tty
        CODE_SIGN_IDENTITY=`echo "${SIGNING_IDS[$DEFAULT_ID]}" | sed "s/\"//g"`
        
        echo "Set Provisioning Profile:" $CODE_SIGN_IDENTITY
    fi
    IFS=$SAVEIFS
    
    # *** Set certificate in xcode
    echo "CODE_SIGN_IDENTITY = ${CODE_SIGN_IDENTITY}" > /tmp/xcode_override.settings
    
    echo "Set Provisioning Profile:" $CODE_SIGN_IDENTITY >> $BUILD_LOG
    popd
}





# sets:     MOBILEPROVISION_NAME   MOBILEPROVISION_FILE
function setProvisioningProfile()
{
    if [ "$CODE_SIGN_IDENTITY" = "" ]; then
        echo "Missing settings for setProvisioningProfile()." >> $BUILD_LOG
        cat $BUILD_LOG
        exit 1
    fi
    
    # test sample:
    # MOBILEPROVISION_URI="${HOME}/Library/MobileDevice/Provisioning Profiles/......mobileprovision"
    # MOBILEPROVISION_FILE="......mobileprovision"
    # MOBILEPROVISION_NAME="....."
    # CODE_SIGN_IDENTITY="......"
    
    
    TEMP_MOBILEPROVISION_PLIST_PATH=/tmp/mobileprovision.plist
    TEMP_CERTIFICATE_PATH=/tmp/certificate.cer
    MOBILEDEVICE_PROVISIONING_PROFILES_FOLDER="${HOME}/Library/MobileDevice/Provisioning Profiles"
    MATCHING_PROFILES_LIST=""
    NAMES=( )
    FILES=( )
    FOUND_PROFILE="FALSE"

    pushd "$MOBILEDEVICE_PROVISIONING_PROFILES_FOLDER"
        for MOBILEPROVISION_FILENAME in *.mobileprovision
        do
            iconv -c -s -t UTF-8 "$MOBILEPROVISION_FILENAME" | sed -n '/<!DOCTYPE plist/,/<\/plist>/ p' > "$TEMP_MOBILEPROVISION_PLIST_PATH" 2>&1
            /usr/libexec/PlistBuddy -c 'Print DeveloperCertificates:0' $TEMP_MOBILEPROVISION_PLIST_PATH > $TEMP_CERTIFICATE_PATH
            MOBILEPROVISION_IDENTITY_NAME=`openssl x509 -inform DER -in $TEMP_CERTIFICATE_PATH -subject -noout | perl -n -e '/CN=(.+)\/OU/ && print "$1"'`
        
            # echo $MOBILEPROVISION_IDENTITY_NAME # TESTING: SHOW ALL FILES
    
            if [ "$CODE_SIGN_IDENTITY" = "$MOBILEPROVISION_IDENTITY_NAME" ]; then
                MOBILEPROVISION_PROFILE_NAME=`/usr/libexec/PlistBuddy -c 'Print Name' $TEMP_MOBILEPROVISION_PLIST_PATH`
                if [ "$MOBILEPROVISION_NAME" = "$MOBILEPROVISION_PROFILE_NAME" ]; then
                    FOUND_PROFILE="TRUE"
                    MOBILEPROVISION_FILE="\"$MOBILEPROVISION_FILENAME\""
                fi
            
                FILES=( "${FILES[@]}" "\"$MOBILEPROVISION_FILENAME\"" )
                NAMES=( "${NAMES[@]}" "\"$MOBILEPROVISION_PROFILE_NAME\"" )
            fi
        done
    
    if [ "$NAMES" = "" ]; then
        echo "No provisioning profile found for \"$CODE_SIGN_IDENTITY\""
        exit 1
    fi
    
    # select a provisioning profile
    if [ $FOUND_PROFILE = "FALSE" ]; then 
        echo "No default provisioning profile set."
        for (( i=0; i < ${#NAMES[@]}; i++ )); do
            echo [$i]: "${NAMES[$i]}"
        done

        echo "Select a provisioning profile [default 0]: "
        read DEFAULT_ID </dev/tty
        
        MOBILEPROVISION_NAME=${NAMES[$DEFAULT_ID]}
        FILE=`echo ${FILES[$DEFAULT_ID]} | tr -d '"'`
        MOBILEPROVISION_FILE="$MOBILEDEVICE_PROVISIONING_PROFILES_FOLDER"/$FILE
    
        echo Selected profile: $MOBILEPROVISION_NAME using provisioning file $MOBILEPROVISION_FILE
    fi
    
    echo selected profile \"$MOBILEPROVISION_NAME\" with file $MOBILEPROVISION_FILE >> $BUILD_LOG
}






function updateBuildVersion() 
{
    # Test Sample:
    # INFOPLIST_FILE='/Volumes/PixieDust/src/PixieDust/PixieDust-Info.plist' 
    
    # INFOPLIST_FILE=$1 # matches xcode scheme env var
    VERSION_TYPE=${2:-'revision'}

    BUILD_VERSION=`/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $INFOPLIST_FILE`
    REVISION_VERSION=`/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $INFOPLIST_FILE`

    major=`echo $BUILD_VERSION | cut -d. -f1`
    minor=`echo $BUILD_VERSION | cut -d. -f2`
    revision=$REVISION_VERSION
    if [ "$VERSION_TYPE" = "major" ]; then
        major=`expr $major + 1`
    elif [ "$VERSION_TYPE" = "minor" ]; then
        minor=`expr $minor + 1`
    else
        revision=`expr $revision + 1`
    fi
    BUILD_VERSION="$major.$minor"

    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${BUILD_VERSION}" $INFOPLIST_FILE
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${revision}" $INFOPLIST_FILE
    
    echo $BUILD_VERSION
}








function buildProject()
{
    # Test Sample:
    # XCODE_WORKSPACE="/Volumes/PixieDust/src/PixieDust.xcodeproj/project.xcworkspace"
    # XCODE_SCHEME="PixieDust"
    
    if [ "$XCODE_WORKSPACE" = "" || "$XCODE_SCHEME" = "" || "$ARCHIVE_ROOT" = ""]; then
        echo "Missing settings for buildProject()." >> $BUILD_LOG
        cat $BUILD_LOG
        exit 1
    fi

    echo "building project..."
    
    # store list of achives
    SAVEIFS=$IFS
    IFS=$'\n'
    prev=( $(find "$ARCHIVE_ROOT" -iname *.xcarchive) )
    IFS=$SAVEIFS
        
    /usr/bin/xcodebuild -workspace $XCODE_WORKSPACE -scheme $XCODE_SCHEME clean archive \
        -xcconfig /tmp/xcode_override.settings > /tmp/xcodebuild.log 2>&1
    
    echo "build ended" >> $BUILD_LOG
    
    # find all files again 
    SAVEIFS=$IFS
    IFS=$'\n'
    brandnew=( $(find "$ARCHIVE_ROOT" -iname *.xcarchive) )
    
    # save out the new binaries
    ARCHIVE_XCODE=$(comm -13  <(echo "${prev[*]}") <(echo "${brandnew[*]}"))
    
    ARCHIVE_APP="$ARCHIVE_XCODE/Products/Applications/"$(ls "$ARCHIVE_XCODE/Products/Applications" | grep .app)
    ARCHIVE_DSYM="$ARCHIVE_XCODE/dSYMs/"$(ls "$ARCHIVE_XCODE/dSYMs" | grep .dSYM)
    IFS=$SAVEIFS
    
    echo "New Archive found ${ARCHIVE_XCODE}" >> $BUILD_LOG
    echo "New App found ${ARCHIVE_APP}" >> $BUILD_LOG
    
    if [ "$?" -ne 0 ]; then
        echo "There were errors building the project in xcode." >> $BUILD_LOG
        cat $BUILD_LOG  
        /usr/bin/open -a /Applications/Utilities/Console.app /tmp/xcodebuild.log
        exit 1
    fi
    
    echo >> $BUILD_LOG
    echo "Completed Project Build." >> $BUILD_LOG
    
}








function createAPP ()
{
    if [ "$SOURCE_ROOT" = "" || "$ARCHIVE_APP" = "" || $ARCHIVE_DSYM = "" || "$MOBILEPROVISION_FILE" = "" || "$CODE_SIGN_IDENTITY" = "" ]; then
        echo "Missing settings for createIPA()." >> $BUILD_LOG
        open $BUILD_LOG
        exit 1
    fi
    
    DSYM_TARGET="$LOCAL_DIR"/bin/"$XCODE_TARGET".dSYMs.zip
    IPA_TARGET="$LOCAL_DIR"/bin/"$XCODE_TARGET".ipa

    echo >> $BUILD_LOG
    echo "Creating APP." >> $BUILD_LOG
    # echo "app ${ARCHIVE_APP}" >> $BUILD_LOG
    # echo "prov ${MOBILEPROVISION_FILE}" >> $BUILD_LOG
    # echo /usr/bin/xcrun -sdk iphoneos PackageApplication "..." -o /tmp/app.ipa --embed "..." --sign "..."
    
    /usr/bin/xcrun -sdk iphoneos PackageApplication "${ARCHIVE_APP}" -o "$IPA_TARGET" >> $BUILD_LOG 2>&1
    
    # /usr/bin/xcrun -sdk iphoneos PackageApplication "${ARCHIVE_APP}" -o /tmp/app.ipa --embed "$MOBILEPROVISION_FILE" --sign "${CODE_SIGN_IDENTITY}" >> $BUILD_LOG 2>&1
    
    FILE=$(basename "$ARCHIVE_XCODE")
    pushd $(dirname "$ARCHIVE_XCODE")
    /usr/bin/zip -r "$DSYM_TARGET" "$FILE" >> $BUILD_LOG 2>&1
    
    if [ "$?" -ne 0 ]; then
        echo "$MOBILEPROVISION_FILE"
        echo "$ARCHIVE_DSYM"
        echo "There were errors creating APP." >> $BUILD_LOG
        open $BUILD_LOG
        exit 1
    fi
}










function gitReleaseNotes()
{
    pushd $GIT_ROOT
    
    TAGS=`git for-each-ref --sort='-*authordate' --format='%(refname:short)' refs/tags`
    LAST_TAG=`echo $TAGS | tail -2 | sed '2d' $1`
    PREV_TAG=`echo $TAGS | tail -1`
    LAST_COMMIT=`git rev-list $LAST_TAG | head -n 1`
    PREV_COMMIT=`git rev-list $PREV_TAG | head -n 1`
    RELEASE_NOTES=`git log --pretty=format:"%s (%cd)" --abbrev-commit "$LAST_COMMIT"..HEAD`
    
    echo "$RELEASE_NOTES"
    
    popd
}









function gitTagRelease()
{
    git tag $BUILD_VERSION -m"[BUILD] - $BUILD_VERSION\n\n$RELEASE_NOTES"
}










function uploadTestFlight()
{
    if [ "$API_TOKEN" = "" || "$TEAM_TOKEN" = "" ]; then
        echo "Missing settings for uploadTestFlight()." >> $BUILD_LOG
        cat $BUILD_LOG
        exit 1
    fi
    
    SHOULD_NOTIFY=${SHOULD_NOTIFY:-"False"}
    DISTRIBUTION_LISTS=${DISTRIBUTION_LISTS:-""}
    RELEASE_NOTES=${RELEASE_NOTES:-" "}
    
    # -F dsym=@"$DSYM_TARGET" \
    
    /usr/bin/curl "http://testflightapp.com/api/builds.json" \
    -F file=@"$IPA_TARGET" \
    -F team_token="$TESTFLIGHT_TEAM_TOKEN" \
    -F api_token="$TESTFLIGHT_API_TOKEN" \
    -F notify="$TESTFLIGHT_SHOULD_NOTIFY" \
    -F distribution_lists="$TESTFLIGHT_DISTRIBUTION_LIST" \
    -F notes="$RELEASE_NOTES" >> $BUILD_LOG 2>&1

    if [ "$?" -ne 0 ]; then
        echo "Couldn't upload build." >> $BUILD_LOG
        cat $BUILD_LOG
        exit 1
    fi
    
    echo "Uploaded to $BUILD_VERSION to TestFlight!" >> $BUILD_LOG
    
    if [ "$SHOULD_OPEN_TESTFLIGHT_DASHBOARD" = "True" ]; then
        /usr/bin/open "https://testflightapp.com/dashboard/builds/"
    fi
}



run