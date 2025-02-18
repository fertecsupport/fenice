#!/bin/bash
DATE="$(date +%Y-%m-%d_%H.%M.%S.%3N)"

# WORKSPACE_FOLDER=/home/pi/workspace/neuron/ # variabile di ambiente impostata nella definizione del servizio (neuron/fenice/...)-autoupdate.service
# PROJECT_NAME=$(basename $WORKSPACE_FOLDER)  # also variabile di ambiente
PROJECT_NAME_LOWERCASE="${PROJECT_NAME,,}"
UPDATEID=$(cat /dev/urandom | head -c 4 | od -vt x1 -A n | sed 's/ //g')
CLIENT_SERVER_ADDRESS=http://localhost:5566

AUTOUPDATE_FOLDER=${WORKSPACE_FOLDER}autoupdate/
START_SCRIPT_FILENAME=start.sh

FIRST_INSTALL=false
AUTOUPDATE_FOLDER_CREATED=false

# versione compatibile con usbmount
MOUNT_PATH=/media/usb*/
RUN_AUTOUPDATE=true
IS_MOUNTED_EVENT=false
DEVICE_IS_MOUNTED=false

for arg in "$@"
do
	if [[ $arg == "--mount-path="* ]]; then
		# versione compatibile con udiskie (arch)
		MOUNT_PATH="${arg#*=}/*"
	elif [[ $arg == "--event=device_mounted" ]]; then
		IS_MOUNTED_EVENT=true
		RUN_AUTOUPDATE=false
	elif [[ $arg == "--is-mounted=True" ]]; then
		DEVICE_IS_MOUNTED=true
		RUN_AUTOUPDATE=false
	elif [[ $arg == "--event=device_"* ]]; then
		RUN_AUTOUPDATE=false
	fi
done

if ! ($RUN_AUTOUPDATE || ($IS_MOUNTED_EVENT && $DEVICE_IS_MOUNTED) )
then
	echo "Ignoring auto update - args: $@"

	exit 0
fi

if [ ! -d "$WORKSPACE_FOLDER" ]
then 
	mkdir -p "$WORKSPACE_FOLDER"

	FIRST_INSTALL=true
elif [ ! -f "${WORKSPACE_FOLDER}$START_SCRIPT_FILENAME" ]
then 
	FIRST_INSTALL=true
fi

if [ ! -d $AUTOUPDATE_FOLDER ]
then 
	mkdir -p $AUTOUPDATE_FOLDER

	AUTOUPDATE_FOLDER_CREATED=true
fi

AUTOUPDATE_FOLDER="$AUTOUPDATE_FOLDER${DATE}_$UPDATEID/"
mkdir -p $AUTOUPDATE_FOLDER

UPDATE_FILE=${AUTOUPDATE_FOLDER}autoupdate.$DATE.$UPDATEID

SRC_AUTOUPDATE_FOLDER_NAME="$PROJECT_NAME_LOWERCASE-autoupdate/"

# crea file autoupdate per info
touch $UPDATE_FILE

# scans for hidden files
shopt -s dotglob

has_param() {
    local term="$1"
    shift
    for arg; do
        if [[ $arg == "$term" ]]; then
            return 0
        fi
    done
    return 1
}

log_line() {
	local LINE="$@"
	
	if [ ! -z "$LINE" ]
	then
		LINE="[$(date '+%Y-%m-%d %H:%M:%S.%3N')] $LINE"
	fi

	echo "$LINE"
    echo "$LINE" >> $UPDATE_FILE
}

DEBUG_MESSAGE_TYPE=debug
send_curl_message() {
	local LOG_MSG="sending ${1^^} message to client"

	if [[ "$1" != "$DEBUG_MESSAGE_TYPE" ]]
	then
		LOG_MSG="$LOG_MSG: $2"
	fi

	log_line "$LOG_MSG"
	
	local CURL_RESULT=$(curl -X POST "$CLIENT_SERVER_ADDRESS/$1" -d "$2")
	log_line "$CURL_RESULT"
	log_line
}

send_warning_message() {
	send_curl_message alarm $1
}

send_success_message() {
	send_curl_message success $1
}

send_debug_message() {
	if [[ $IS_DEBUG == 0 ]]
	then
		local MESSAGE="$(cat $UPDATE_FILE)"

		send_curl_message "$DEBUG_MESSAGE_TYPE" "$MESSAGE"
	fi
}

log_dir_content() {
	log_line "=== Folder content $1 ==="

	for e in $1* ; do
	    log_line "$e"
	done

	log_line "======"
	log_line
}

file_ends_with_newline() {
    [[ $(tail -c1 "$1" | wc -l) -gt 0 ]]
}

insert_row() {
	local IDX=$1
	local TXT=$2
	local FILE=$3

	local FILE_LEN=$(sed -n '$=' $FILE)
	log_line "INSERT_ROW: idx=$IDX - file len=$FILE_LEN"

	if [[ $IDX -ge $(($FILE_LEN + 1)) ]]
	then
		log_line "INSERT_ROW: appending line"
		echo "$TXT" >> $FILE
	else
		sed -i "${IDX} i ${TXT}" $FILE
	fi
}

delete_row() {
	local IDX=$1
	local FILE=$2

	local FILE_LEN=$(sed -n '$=' $FILE)
	log_line "DELETING ROW $IDX FROM FILE (len=$FILE_LEN) $FILE"

	sed -i "${IDX} d" $FILE
}

give_execute_permission() {
	if [ -e "$1" ]
	then 
		chmod +x "$1"
	fi
}

TAR_ARG=--tar
backup_file() {
	local FULLPATH=$1
	local FILENAME=$(basename ${FULLPATH})

	if [[ $* == *"$TAR_ARG"* ]]
	then
		tar -czf "${AUTOUPDATE_FOLDER}${FILENAME}.bkp.$DATE.$UPDATEID.tar.gz" -C $WORKSPACE_FOLDER $FULLPATH
	else
    	cp $FULLPATH "${AUTOUPDATE_FOLDER}${FILENAME}.bkp.$DATE.$UPDATEID"
	fi
}

find_workspace_folder() {
	for d in $MOUNT_PATH ; do
	    AUTOUPDATE_SOURCE_FOLDER="${d}$SRC_AUTOUPDATE_FOLDER_NAME"

		log_line "Checking if $PROJECT_NAME folder exists: $AUTOUPDATE_SOURCE_FOLDER"
		log_line

	    if [ -e "$AUTOUPDATE_SOURCE_FOLDER" ]
		then 
			break
		elif [ "$(basename "$d")" = "$(basename "$SRC_AUTOUPDATE_FOLDER_NAME")" ]
		then
			AUTOUPDATE_SOURCE_FOLDER="$d"/
			break
		else
			AUTOUPDATE_SOURCE_FOLDER=""
		fi
	done
}

load_docker_images() {
	local DOCKER_IMAGES_DIR=${AUTOUPDATE_SOURCE_FOLDER}docker-images/
	if [ -d $DOCKER_IMAGES_DIR ]
	then 
		log_dir_content $DOCKER_IMAGES_DIR

		for e in $DOCKER_IMAGES_DIR*.tar ; do
		    log_line "-> found docker image tar: $e"

			LOAD_RESULT=$( docker load --input $e )

		    log_line "Load result:"
		    log_line "$LOAD_RESULT"
		    log_line
		done
	fi
}

load_env_keys() {
	local ENVFILE=${AUTOUPDATE_SOURCE_FOLDER}env
	if [ ! -e $ENVFILE ]
	then
		ENVFILE=${AUTOUPDATE_SOURCE_FOLDER}.env
	fi 

	if [ -e $ENVFILE ]
	then
	    log_line "found .env file: $ENVFILE"
		log_line

	    local ORIGINAL_ENV_FILE=$WORKSPACE_FOLDER.env

		# split chiavi e sostituzione se esistono nel file originale

		if [ -e $ORIGINAL_ENV_FILE ]
		then
	    	backup_file $ORIGINAL_ENV_FILE

			while IFS= read -r line || [ -n "$line" ]; do
			    log_line env line:
			    log_line $line
			    log_line

			    if [[ $line == \#* ]]
		    	then
		    		log_line	"__ skipping commented line \"$line\""
			    	log_line
		    		continue
		    	fi

			    if [[ ! $line =~ "=" ]]
		    	then
		    		log_line	"__ skipping line without key value format \"$line\""
			    	log_line
		    		continue
		    	fi

			    local ENV_LINE_IDX=0
			    local ENV_FOUND_LINE_IDX=-1

			    local ENV_PARTS=(${line//=/ })

			    local ENV_KEY=${ENV_PARTS[0]}
			    local ENV_VALUE=${ENV_PARTS[1]}

			    log_line "key: \"$ENV_KEY\" - value: \"$ENV_VALUE\""

				local COMMENT="# inserted with autoupdate at $DATE - envfile: $ENVFILE"

		    	while IFS= read -r origline || [ -n "$origline" ]; do
					ENV_LINE_IDX=$((ENV_LINE_IDX+1))

					# log_line "_____ original line $ENV_LINE_IDX: $origline"

					if [[ "$origline" = "$ENV_KEY"* ]]
					then
						log_line "found key $ENV_KEY in line $ENV_LINE_IDX"

						ENV_FOUND_LINE_IDX=$ENV_LINE_IDX
						break
					fi
				done < "$ORIGINAL_ENV_FILE"

				if [[ $ENV_FOUND_LINE_IDX -eq -1 ]]
				then
					log_line "-> appending new value: \"$line\""

					if ! file_ends_with_newline $ORIGINAL_ENV_FILE
					then
						echo "" >> $ORIGINAL_ENV_FILE
					fi

					echo $COMMENT >> $ORIGINAL_ENV_FILE

					echo $line >> $ORIGINAL_ENV_FILE
				else
					if [ "$line" = "$origline" ]
					then
			    		log_line "__ skipping line already present \"$line\""
			   			log_line
			    		continue
					fi

					# commento la riga originale
					delete_row $ENV_FOUND_LINE_IDX $ORIGINAL_ENV_FILE
					insert_row $ENV_FOUND_LINE_IDX "# $origline" $ORIGINAL_ENV_FILE

					log_line

					# inserisco nella riga successiva la riga modificata

					INSERT_IDX=$((ENV_FOUND_LINE_IDX + 1)) # 1-indexed

					log_line "-> inserting new value at position $INSERT_IDX: \"$line\""

					insert_row $INSERT_IDX "$line" $ORIGINAL_ENV_FILE

					# inserisco nella riga precedente un commento che dice "da file .env in data odierna"
					COMMENT_IDX=$INSERT_IDX

					log_line "-> inserting comment at position $COMMENT_IDX: \"$COMMENT\""

					insert_row $COMMENT_IDX "$COMMENT" $ORIGINAL_ENV_FILE
				fi

				log_line
			done < "$ENVFILE"
		else
			cp $ENVFILE $ORIGINAL_ENV_FILE

		    log_line ".env file copied to: $ORIGINAL_ENV_FILE"
			log_line
		fi
	fi
}

load_docker_compose() {
	local DOCKERCOMPOSE_FILE

	for dc in ${AUTOUPDATE_SOURCE_FOLDER}docker-compose*.y*ml; do

		local DOCKERCOMPOSE_FILENAME=$(basename ${dc})

		log_line "searching for docker file $DOCKERCOMPOSE_FILENAME"

	    [ ! -e "$dc" ] && continue

	    # verifico che esista un docker compose chiamato allo stesso nome nella cartella workspace
	    DOCKERCOMPOSE_FILE=${WORKSPACE_FOLDER}$DOCKERCOMPOSE_FILENAME

		local LBL="created from"

		if [ -e "$DOCKERCOMPOSE_FILE" ]
		then
		    log_line "found docker-compose file: $DOCKERCOMPOSE_FILE"
			log_line

			LBL="replaced with"

			backup_file $DOCKERCOMPOSE_FILE
		fi

		cp $dc $DOCKERCOMPOSE_FILE

	    log_line "docker-compose file $LBL $dc"
		log_line
	done
}

get_asset_path() {
	echo ${AUTOUPDATE_SOURCE_FOLDER}$1
}

load_asset() {
	local ASSET_NAME="$1"
	local ASSET_PATH=$(get_asset_path "$ASSET_NAME")

	if [ -e "$ASSET_PATH" ]
	then
		local WORKSPACE_ASSET="$2"
		if [ -z "$WORKSPACE_ASSET" ]
		then
			WORKSPACE_ASSET="${WORKSPACE_FOLDER}$ASSET_NAME"
		fi

		log_line "loading asset: $WORKSPACE_ASSET"

		local LBL="created from"

		if [ -e "$WORKSPACE_ASSET" ]
		then
		    log_line "found $ASSET_NAME file: $WORKSPACE_ASSET"

			LBL="replaced with"

			backup_file $WORKSPACE_ASSET
		fi

		cp $ASSET_PATH $WORKSPACE_ASSET

	    log_line "$WORKSPACE_ASSET file $LBL $ASSET_PATH"
		log_line
	fi
}

get_asset_folder_path() {
	echo ${AUTOUPDATE_SOURCE_FOLDER}$1
}

load_asset_folder() {
	local ASSET_DIR=$1
	local ASSET_DIR_PATH=$(get_asset_folder_path $ASSET_DIR)
	local ASSET_LABEL=$(basename $ASSET_DIR_PATH)

	if [ -d $ASSET_DIR_PATH ]
	then 
		local WORKSPACE_ASSET_DIR="${WORKSPACE_FOLDER}${ASSET_DIR}"

		local LBL="created from"

		if [ -d $WORKSPACE_ASSET_DIR ]
		then 
		    log_line "found $ASSET_LABEL directory: $WORKSPACE_ASSET_DIR"

			# comprimo e backuppo
			backup_file $ASSET_DIR $TAR_ARG

			LBL="merged with"
		fi

		cp -rf $ASSET_DIR_PATH $WORKSPACE_FOLDER

	    log_line "$ASSET_LABEL directory $LBL $ASSET_DIR_PATH"
		log_line
	fi
}

SETTINGS_TXT_FILENAME=settings.txt

load_settings_txt() {
	local SETTINGS_TXT_FILENAME="$SETTINGS_TXT_FILENAME"

	load_asset "$SETTINGS_TXT_FILENAME"
}

load_start_script() {
	load_asset "$START_SCRIPT_FILENAME"

	give_execute_permission "${WORKSPACE_FOLDER}$START_SCRIPT_FILENAME"
}

load_fullscreen_script() {
	local FULLSC_FILENAME="${PROJECT_NAME_LOWERCASE}_client_fullsc.sh"

	load_asset "$FULLSC_FILENAME"

	give_execute_permission "${WORKSPACE_FOLDER}$FULLSC_FILENAME"
}

load_desktop_background_script() {
	local DESKTOP_BG_SCRIPT_FILENAME="feh_bg.sh"

	load_asset "$DESKTOP_BG_SCRIPT_FILENAME"

	give_execute_permission "${WORKSPACE_FOLDER}$DESKTOP_BG_SCRIPT_FILENAME"
}

load_labels() {
	local ASSET_FOLDER=labels/

	load_asset_folder "$ASSET_FOLDER"
}

load_images() {
	local ASSET_FOLDER=assets/

	load_asset_folder "$ASSET_FOLDER"
}

load_components() {	
	local ASSET_FOLDER=components/

	load_asset_folder "$ASSET_FOLDER"
}

load_dapr_files() {
	local ASSET_FOLDER=dapr_files/

	load_asset_folder "$ASSET_FOLDER"
}

load_mono_app() {
	local MONO_FOLDER=mono/
	local MONO_FOLDER_PATH=$(get_asset_folder_path "$MONO_FOLDER")

	if [ -d $MONO_FOLDER_PATH ]
	then
		# kill mono process
		log_line "Found mono update folder: $MONO_FOLDER_PATH"

		# cerco i file .exe nella cartella mono e kill-o eventuali processi che usano lo stesso eseguibile
		for exe in ${MONO_FOLDER_PATH}*.exe ; do
			log_line "Found executable: $exe"
			log_line

			local EXE_NAME=$(basename $exe)
			local EXE_PID=$(ps aux | grep "[m]ono .*$EXE_NAME" | awk '{print $2}')
			# local EXE_PID=$( ps aux | grep "[s]leep 100000" | awk '{print $2}')
			if [ ! -z "$EXE_PID" ]
			then
				log_line "Killing mono process for executable $EXE_NAME with pid $EXE_PID"
				log_line

				log_line "Process $EXE_PID of executable $EXE_NAME: $EXE_KILL"
				log_line "$(kill $EXE_PID)"
			fi
		done

		# load new content
		load_asset_folder "$MONO_FOLDER"
	fi
}

UTILITIES_FOLDER=utilities/

load_utilities() {
	local ASSET_FOLDER="$UTILITIES_FOLDER"

	load_asset_folder "$ASSET_FOLDER"

	give_execute_permission "${WORKSPACE_FOLDER}${ASSET_FOLDER}Fenice.settingsParser"
	give_execute_permission "${WORKSPACE_FOLDER}${ASSET_FOLDER}seed_db.sh"
}

seed_db() {
	# lancio il seed se esiste un file settings.txt nella chiavetta
	local SETTINGS_TXT_PATH=$(get_asset_path $SETTINGS_TXT_FILENAME)

	if [ -f "$SETTINGS_TXT_PATH" ]
	then
		local SEED_SCRIPT="${WORKSPACE_FOLDER}${UTILITIES_FOLDER}seed_db.sh"
		
		if [ -f "$SEED_SCRIPT" ]
		then
			if [ "$FIRST_INSTALL" = true ]
			then
				log_line "Spawning docker containers for the first time..."
				log_line
				
				"${WORKSPACE_FOLDER}$START_SCRIPT_FILENAME" --headless
			fi
		
			log_line "Seeding database with script: $SEED_SCRIPT"
		
			local SEED_RESULT="$($SEED_SCRIPT)"
			
			log_line "$SEED_RESULT"
			log_line
			
			if [ "$FIRST_INSTALL" = true ]
			then
				log_line "Shutting down docker containers..."
				log_line
				
				docker-compose down
			fi
		fi
	fi
}

update_autoupdate() {
	local ASSET_NAME="$PROJECT_NAME_LOWERCASE-autoupdate.sh"
	local LOCAL_ASSET="/home/$USER/scripts/${ASSET_NAME}"

	load_asset "$ASSET_NAME" "$LOCAL_ASSET"
}

reboot_system() {
	# restart if not debugging
	if [[ $IS_DEBUG != 0 ]]
	then
		log_line rebooting

		systemctl --message="$PROJECT_NAME autoupdate - id: $UPDATEID" reboot
		sleep 30
	else
		log_line "debug mode, skipping reboot"
	fi
}

log_line "Update $UPDATEID starting..."
log_line "User: $USER"
log_line "Project name: $PROJECT_NAME"
log_line "Workspace folder: $WORKSPACE_FOLDER"
log_line "Args: $@"

# sleep 2

if [ "$FIRST_INSTALL" = true ]
then
	log_line "Workspace folder created: $WORKSPACE_FOLDER"
	log_line
fi

if [ $AUTOUPDATE_FOLDER_CREATED ]
then
	log_line "Autoupdate folder created: $AUTOUPDATE_FOLDER"
	log_line
fi

find_workspace_folder

log_line

if [ -z "$AUTOUPDATE_SOURCE_FOLDER" ]
then
	log_line "No autoupdate folder found on device: $SRC_AUTOUPDATE_FOLDER_NAME"

	send_warning_message $((0xE1)) # cartella non trovata

	exit 0
else
	log_line "Workspace folder found: $AUTOUPDATE_SOURCE_FOLDER"
	log_line
fi

[ -f "$(get_asset_path .debug)" ]
IS_DEBUG=$?
log_line "Debug mode (0 means it is): $IS_DEBUG"
log_line

send_success_message $((0xF0)) # aggiornamento applicazione...

sleep 2

log_dir_content $AUTOUPDATE_SOURCE_FOLDER

log_line

# controllo immagini docker
log_line "### checking docker images..."
log_line

load_docker_images

# controllo file settings.txt
log_line "### checking settings.txt file..."
log_line

load_settings_txt

# controllo file .env
log_line "### checking .env file..."
log_line

load_env_keys

# sostituzione file docker-compose
log_line "### checking docker-compose files..."
log_line

load_docker_compose

# controllo script start.sh
log_line "### checking start script..."
log_line

load_start_script

# controllo script fullscreen.sh
log_line "### checking fullscreen script..."
log_line

load_fullscreen_script

# controllo script fah_bg.sh
log_line "### checking virtual desktop background script..."
log_line

load_desktop_background_script

# controllo cartella labels
log_line "### checking labels..."
log_line

load_labels

# controllo cartella assets
log_line "### checking images..."
log_line

load_images

# controllo cartella components
log_line "### checking components..."
log_line

load_components

# controllo cartella dapr_files
log_line "### checking dapr files..."
log_line

load_dapr_files

# controllo cartella mono
log_line "### checking mono application..."
log_line

load_mono_app

# controllo cartella utilities
log_line "### checking utilities..."
log_line

load_utilities

seed_db

# controllo cartella utilities
log_line "### checking autoupdate script..."
log_line

update_autoupdate

send_success_message $((0xF1)) # app aggiornata con successo

send_debug_message

log_line
log_line "Update $UPDATEID done"

sleep 5

reboot_system