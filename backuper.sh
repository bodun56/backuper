#!/bin/bash
VERSION="2019.04.12"

source /etc/backuper/backuper.cfg

#Выключение сервиса
function NetworkOnToUp {
	systemctl disable netoff.service
}

#Включение сервиса
function NetworkOffToUp {
	systemctl enable netoff.service
}

#Включение сети
function networkUP {
	systemctl restart network
}

#Выключение сети
function networkDown {
	systemctl stop network
}

#Проверка свободного места
function querySpace {
	IFS=' ' read -r -a array <<< $(df -hk --output=avail ${Hard[0]})
	STYPE=${array[1]}
	MHS=$(($MinHardSpace * 1024 * 1024))
	if (( "$STYPE" <= "$MHS" ))
	then
	    log "Необходима очиста"
	    startClear
	    querySpace
	else
	    log "Очистка не нужна"
	fi
}

#Синхронизация жёстких дисков
function startSyncHards {
	log "Синхронизация жёстких дисков"
	h=1
	for HARD in ${Hard[@]}
	do
		if [[ "$HARD" != "${Hard[0]}" ]]
		then
			if [[ $(mount | grep "$HARD") == "" ]]
			then
				log "$HARD не примонтирован\t[failed]"
			else
				log "$h: $HARD синхронизируется с ${Hard[0]}"
				if [[ "$Checksum" == "true" ]]
				then
					rsync -c --stats -uhv --recursive --progress --delete ${Hard[0]}/ $HARD/
				else
					rsync --stats -uhv --recursive --progress --delete ${Hard[0]}/ $HARD/
				fi
				h=$((++h))
			fi
		fi
	done
	log "Синхронизация завершена"
}

#--config-log
function configLog {
	IFS='=' read -r -a array <<< $1
	if [[ "${array[1]}" == "" ]]
	then
		echo "Не указано имя конфига"
	else
		if [[ ! -f "$ConfigPath/${array[1]}.cfg" ]]
		then
			echo "${array[1]} не обнаружен"
		else
			grep "[${array[1]}]" $LogDir/$LogName
		fi
	fi
}

#--config-log-error
function configLogError {
	grep "error" $LogDir/$LogName
}

#--config-log-failed
function configLogFailed {
	grep "failed" $LogDir/$LogName
}

function readLog {
	less $LogDir/$LogName
}

function logln {
	printf "$1"
	printf "$1" >> $LogDir/$LogName
}

function log {
	dnow=`date +"%Y.%m.%d %H:%M:%S"`
	printf "[$dnow] $1\n"
	printf "[$dnow] $1\n" >> $LogDir/$LogName
}

#Чтение и вывод настроек
function getsettings {
	echo "Текущие настройки"
	
	printf "Включение и отключение сети\t"
	if [[ "$NetworkUpDown" == true ]]
	then
		printf "[включено]"
	else
		printf "[выключено]"
	fi
	printf "\n"
	
	printf "Указано хардов ${#Hard[@]}:\n"
	for i in ${Hard[@]}
	do
		echo "$i"
	done
	
	echo "Каталог хранения логов: $LogDir"
	echo "Каталог конфигов: $ConfigPath"	
}

#Создание стандартного конфига
function makeDefaultConfig {
	if [[ -f $ConfigPath/default.cfg ]]
	then
		rm -f $ConfigPath/default.cfg
	fi
	echo "Active=false" >> $ConfigPath/default.cfg
	echo "IpAddr=127.0.0.1" >> $ConfigPath/default.cfg
	echo "Authorization=false" >> $ConfigPath/default.cfg
	echo "UserLogin=user" >> $ConfigPath/default.cfg
	echo "UserPassword=pass" >> $ConfigPath/default.cfg
	echo "DirMount=lan" >> $ConfigPath/default.cfg
	echo "Period=0" >> $ConfigPath/default.cfg
	echo "PathOut=default" >> $ConfigPath/default.cfg
	echo "PathInHost=" >> $ConfigPath/default.cfg
}

#Список конфигов
function listConfig {
	printf "Название\tСостояние\n"
	IFS='.' read -r -a array <<< $(ls -1 $ConfigPath | grep ".cfg")
	for n in ${array[@]}
	do
		if [[ $n != "cfg" ]]
		then
			printf $n
			source "$ConfigPath/$n.cfg"
			case "$Active" in
				"true") printf "\t\t[активен]";;
				"false") printf "\t\t[отключен]";;
			esac
			printf "\n"
		fi
	done
}

#Добавление конфига
function addConfig {
	echo "Создание конфига пользователем"
	echo -n "Название конфига: "
	read addConfigName
	
	echo -n "Включен ли конфиг (y|n): "
	read result
	if [[ "$result" == "y" ]]
	then
		addConfigActive=true
	else
		addConfigActive=false
	fi
	
	echo -n "IP адрес сервера: "
	read addConfigIP
	
	echo -n "Требуется ли логин и пароль (y|n): "
	read useAuth
	if [[ $useAuth == "y" || $useAuth == "Y" ]]
	then
		addConfigAuthorization=true
	
		echo -n "Имя пользователя: "
		read addConfigUserLogin

		echo -n "Пароль: "
		read -s addConfigUserPassword
		printf "\n"
	else
		addConfigAuthorization=false
	fi
	
	echo -n "Каталог монтируемый на удалённом сервере: "
	read addConfigDirMount
	
	echo -n "Периодический запуск каждые х дней [0 каждый день, 1 через день и так далее]: "
	read addConfigPeriod
	
	echo -n "Название каталога для хранения бекапов: "
	read addConfigPathOut
	
	echo -n "Внутрений каталог на удалённом сервере из которого нужно забрать: "
	read addConfigPathInHost
	
	###
	printf "Добавление исключающих масок файлов, которые НЕ БУДУТ учавствовать в синхронизации\nПример *.csv\nПример *.sql\nПример *filename*\n"
	echo -n "Есть ли файлы которые не нужно копировать? (y|n): "
	read ExcludesFilesResult
	if [[ "$ExcludesFilesResult" == "y" || "$ExcludesFilesResult" == "Y" ]]
	then
		ExcludeFilesStop=false
		ExcludeFilesCount=0

		while [ "$ExcludeFilesStop" != true ]
		do
			echo -n "Укажите макску: "
			read ExcludeFiles[$ExcludeFilesCount]
			if [[ "${ExcludeFiles[$ExcludeFilesCount]}" == "" ]]
			then
				ExcludeFilesStop=true
				break
			else
				ExcludeFiles[$ExcludeFilesCount]=${ExcludeFiles[$ExcludeFilesCount]}
				ExcludeFilesCount=$(( ++ExcludeFilesCount ))
			fi

			echo -n "Добавить ещё? (y|n): "
			read ExcludesMore
			if [[ "$ExcludesMore" == "n" || "$ExcludesMore" == "" ]]
			then
				ExcludeFilesStop=true
			fi
		done
	fi
	###
	echo -n "Сохраняем? (y|n): "
	read configSave
	if [[ $configSave == "n" ]]
	then
		echo "Ну как хочешь"
		exit
	fi
	if [[ $configSave == "y" || $configSave == "Y" ]]
	then
		echo "Active=$addConfigActive" >> $ConfigPath/$addConfigName.cfg
		echo "IpAddr=$addConfigIP" >> $ConfigPath/$addConfigName.cfg
		echo "Authorization=$addConfigAuthorization" >> $ConfigPath/$addConfigName.cfg
		echo "UserLogin=$addConfigUserLogin" >> $ConfigPath/$addConfigName.cfg
		echo "UserPassword=$addConfigUserPassword" >> $ConfigPath/$addConfigName.cfg
		echo "DirMount=$addConfigDirMount" >> $ConfigPath/$addConfigName.cfg
		echo "Period=$addConfigPeriod" >> $ConfigPath/$addConfigName.cfg
		echo "PathOut=$addConfigPathOut" >> $ConfigPath/$addConfigName.cfg
		echo "PathInHost=$addConfigPathInHost" >> $ConfigPath/$addConfigName.cfg
		if [[ "$ExcludesFilesResult" == "y" || "$ExcludesFilesResult" == "Y" ]]
		then
			i=0
			for EX in ${ExcludeFiles[@]}
			do
				echo "Exclude[$i]=$EX" >> $ConfigPath/$addConfigName.cfg
				i=$((++i))
			done
		else
			echo "Exclude[0]=" >> $ConfigPath/$addConfigName.cfg
		fi
	fi
	echo "" >> $ConfigPath/$addConfigName.cfg
}

#Удаление конфига
function removeConfig {
	IFS='=' read -r -a array <<< $1
	if [[ -f "$ConfigPath/${array[1]}.cfg" ]]
	then
		echo -n "Удалить ${array[1]}? "
		read result
		if [[ "$result" == "y" || "$result" == "Y" || "$result" == "yes" || "$result" == "YES" ]]
		then
			rm -f $ConfigPath/${array[1]}.cfg
			echo "${array[1]} удалён"
		fi
	else
		echo "${array[1]} такого файла нет"
	fi
}

function testconfig {
	logln "[$(date +"%Y.%m.%d %H:%M:%S")] [$1] проверяется "
	testActive=false
	testIpAddr=false
	testUserLogin=false
	testUserPassword=false
	testDirMount=false
	testPeriod=false
	testPathOut=false
	testAuthorization=false
	while read LINE
	do
		if [[ "$testActive" == false && "$LINE" == *Active* ]]
		then
			testActive=true
		fi
		if [[ "$testIpAddr" == false && "$LINE" == *IpAddr* ]]
		then
			testIpAddr=true
		fi
		if [[ "$testAuthorization" == false && "$LINE" == *Authorization* ]]
		then
			testAuthorization=true
		fi
		if [[ "$testUserLogin" == false && "$LINE" == *UserLogin* ]]
		then
			testUserLogin=true
		fi
		if [[ "$testUserPassword" == false && "$LINE" == *UserPassword* ]]
		then
			testUserPassword=true
		fi
		if [[ "$testDirMount" == false && "$LINE" == *DirMount* ]]
		then
			testDirMount=true
		fi
		if [[ "$testPeriod" == false && "$LINE" == *Period* ]]
		then
			testPeriod=true
		fi
		if [[ "$testPathOut" == false && "$LINE" == *PathOut* ]]
		then
			testPathOut=true
		fi
	done < $ConfigPath/$1.cfg
	
	if [[ "$testActive" == true &&
		  "$testIpAddr" == true &&
		  "$testUserLogin" == true &&
		  "$testUserPassword" == true &&
		  "$testDirMount" == true &&
		  "$testPeriod" == true &&
		  "$testPathOut" == true &&
		  "$testAuthorization" == true ]]
	then
		logln "\t\t[ok]\n"
		return 0
	else
		logln "\t[failed]\n"
		log "Конфиг [$1] имеет не все параметры [error]"
		return 1
	fi
}

function listInclude {
	local inc
	local result
	if (( "$#" == "0" ))
	then
		echo "false"
		return
	fi
	
	if [[ "${Include[@]}" == "" ]]
	then
		echo "false"
		return
	fi
	
	for inc in ${Include[@]}
	do
		if [[ "$inc" != "" ]]
		then
			result="$result--include=\"${inc} "
		fi
	done
	echo $result
}

function listIncludePrint {
	local inc	
	logln "[$(datenow)] $cn файлы которые будут включены: "
	for inc in ${Include[@]}
	do
		if [[ "$inc" != "" ]]
		then
			logln "'$inc' "
		fi
	done
	logln "\n"
}

function listExclude {
	local exc
	local result
	if (( "$#" == "0" ))
	then
		echo "false"
		return
	fi
	
	if [[ "${Exclude[@]}" == "" ]]
	then
		echo "false"
		return
	fi
	
	for exc in ${Exclude[@]}
	do
		if [[ "$exc" != "" ]]
		then
			if [[ "$result" == "" ]]
			then
				result="--exclude=${exc}"
			else
				result="${result} --exclude=${exc}"
			fi
		fi
	done
	echo $result
}

function listExcludePrint {
	local exc
	logln "[$(datenow)] $cn файлы которые будут исключены: "
	for exc in ${Exclude[@]}
	do
		if [[ "$exc" != "" ]]
		then
			logln "'$exc' "
		fi
	done
	logln "\n"
}

#для тестов
function test {
	echo "Test:"
	
	exit
}

#Тестирование параметров настроек
function testsettings {
	if [[ ${Hard[@]} == '' ]]
	then
		error 1
	fi
	
	if [[ "$(mount | grep ${Hard[0]})" == "" ]]
	then
		error 0
	fi
	
	if [[ "$NetworkUpDown" == '' ]]
	then
		error 2
	fi
	
	case "$NetworkUpDown" in
		true);;
		false);;
		*) error 3;;
	esac
	
	case $LogMaxSize in
    	''|*[!0-9]*) error 4;;
	esac
	
	case $NetworkSleep in
		''|*[!0-9]*) error 5;;
	esac
	
	#Замещение некоторых настроек по умолчанию
	if [[ "$ConfigPath" == '' ]]
	then
		ConfigPath=/etc/backuper/config
	fi
	
	if [[ "$MountPoint" == '' ]]
	then
		MountPoint=/mnt/backuper
	fi
	
	#Проверка и создание каталогов
	if [[ ! -d $MountPoint ]]
	then
		mkdir $MountPoint
	fi
	
	if [[ ! -d $ConfigPath ]]
	then
		mkdir $ConfigPath
	fi
	
	if [[ ! -d $LogDir ]]
	then
		mkdir $LogDir
	fi
	
	if [[ ! -f $LogDir/$LogName ]]
	then
		touch $LogDir/$LogName
	fi
	
	IFS=' ' read -r -a LogSize <<< $(du -k "$LogDir/$LogName")
	if (( $LogSize > $LogMaxSize ))
	then
		echo "" > $LogDir/$LogName
	fi
	
	if [[ ! -d $PeriodPath ]]
	then
		mkdir $PeriodPath
	fi
}

#Вывод ошибок
function error {
	case $1 in
		0) echo "Hard[0] не примонтирован";;
		1) echo "Не указаны каталоги хранения [Hard[0]]";;
		2) echo "Не указана работа активности сети [NetworkUpDown]";;
		3) echo "Неверный параметр активности сети [NetworkUpDown]";;
		4) echo "Максимальный размер файла лога не является числовым [LogMaxSize]";;
		5) echo "Ожидание сетевого интерфейса должно указываться в цифрах [NetworkSleep]";;
	esac
	exit
}

#Изменение параметров сети
function editSettingsNetwork {
	clear
	echo "Изменение работы сети"
	echo "Данный параметр отвечает за поднятие сетевого интерфейса перед началом работы"
	echo "И после окончания работы отключает сеть"
	echo "Данный параметр имеет значения true или false (работает или нет)"
	echo "Текущее значение установлено в: $NetworkUpDown"
	echo -n "Изменить данный параметр? (y|n): "
	read result
	case $result in
		y)editSettingsSetNetwork;;
		n)echo "Ну хорошо, не трогаем";editSettings;;
		*)echo "Моя твоя не понимает. $result - это что?"; exit;;
	esac
}

#Изменение параметров сети
function editSettingsSetNetwork {
	echo -n "В какой параметр перевести true или false?: "
	read result
	if [[ "$result" == "true" || "$result" == "false" ]]
	then
		setNetworkUpDown="NetworkUpDown=$result"
		i=1
		while read LINE
		do
			if [[ "$LINE" != "" ]]
			then
				if [[ "$LINE" == *NetworkUpDown* ]]
				then
					cfg[$i]=$setNetworkUpDown
				else
					cfg[$i]=$LINE
				fi
				let i++
			fi
		done < backuper.cfg
		echo '' > backuper.cfg
		for c in ${cfg[@]}
		do
			echo $c >> backuper.cfg
		done
		echo "Отлично!"
		sleep 2
		editSettings
	else
		echo "Давай-ка лучше не будет ставить всякие $result сюда"
		exit
	fi
}

#Изменение настроек жёстких дисков
function editSettingsHard {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Добавление жёсткого диска
function editSettingsHardAdd {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Удаление жёсткого диска
function editSettingsHardRemove {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Изменение расположения лога
function editSettingsLogPath {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Изменение имени лога
function editSettingsLogName {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Изменение максимального размера лога
function editSettingsLogMaxSize {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Изменение расположения лога
function editSettingsConfigPath {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Изменение каталога монтирования серверов
function editSettigsMountPoint {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Изменение каталога для периодичности
function editSettingsPeriodPath {
	echo "Не реализовано ещё"
	sleep 2
	editSettings
}

#Изменение основных настроек backuper.cfg
function editSettings {
	clear
	echo "Изменение основных настроек"
	echo "1: Включить или выключить поднятие и опускание сети"
	echo "2: Изменить каталог для жёсткого диска"
	echo "3: Добавить новый каталог для жёсткого диска"
	echo "4: Удалить каталог для жёсткого диска"
	echo "5: Изменить каталог расположения логов"
	echo "6: Изменить имя лога"
	echo "7: Задать максимальный размер лога"
	echo "8: Изменить каталог расположеия конфигов"
	echo "9: Изменить каталог монтирования"
	echo "10: Изменить каталог хранения файлов периодичности"
	echo "x: для выхода"
	
	echo -n "Вариант: "
	read item
	case $item in
		1)editSettingsNetwork;;
		2)editSettingsHard;;
		3)editSettingsHardAdd;;
		4)editSettingsHardRemove;;
		5)editSettingsLogPath;;
		6)editSettingsLogName;;
		7)editSettingsLogMaxSize;;
		8)editSettingsConfigPath;;
		9)editSettigsMountPoint;;
		10)editSettingsPeriodPath;;
		x)echo "Удачи!"; exit;;
		*)echo "Я не знаю, что значит $item"; exit;;
	esac
}

function hardinfo {
	for hard in ${Hard[@]}
	do
		IFS=' ' read -r -a array <<< $(df -hk $hard)
		echo "Информация по $hard"
		echo "Общий объём $(( ((${array[9]} / 1023)) / 1023 ))GB"
		echo "Использовано $(( ((${array[10]} / 1023)) / 1023 ))GB"
		echo "Свободно $(( ((${array[11]} / 1023)) / 1023 ))GB"
		echo "-----------------------------"
	done
}

#Помощь
function help {
echo "Версия от $VERSION
-h --help           = Для справки
--edit-settings     = Изменение основных настроек
--get-settings      = Получение текущих настроек
--set-network-up    = Отключение сервиса отключающего сеть при загрузке системы
--set-network-down  = Включение сервиса отключаещего сеть при загрузке системы
--mc                = Создание стандартного конфига
--add-config        = Создание нового пользовательского конфига
--list-config       = Список конфигов
--remove-config     = Удалить конфиг
--read-log          = Чтение лога, для выхода нажать 'q'
--config-log        = Чтение записей лога о конкретном конфиге
--config-log-error  = Чтение ошибок в логах
--config-log-failed = Чтение ошибок в логах
--hard-info         = Информация по жёстким дискам
--test              = Для тестов
--start				= Запуск

Примеры:
Удаление конфига default: --remove-config=default
Удалить конфиг и сразу вывести список: --remove-config=default --list-config
"
}

function datenow {
	echo $(date +"%Y.%m.%d %H:%M:%S")
}

function listInclude {
	local inc
	local result
	if [[ "$1" == "" ]]
	then
		echo "false"
	fi
	
	for inc in ${Include[@]}
	do
		echo "--include=\"$inc\" "
	done
}

#Начало по синхронизации данных с удалённого хоста
function startRSYNC {
	local rsyncParams
	includes=""
	excludes=""
	log "$cn Начало синхронизации"
	DIRNOW=$(date +"%Y_%m_%d")
	if [[ ! -d ${Hard[0]}/$PathOut ]]
	then
		mkdir ${Hard[0]}/$PathOut
	fi
	
	if [[ ! -d ${Hard[0]}/$PathOut/$DIRNOW ]]
	then
		mkdir ${Hard[0]}/$PathOut/$DIRNOW
	fi
	
	if [[ "$Debug" == "true" ]]
	then
		rsyncParams="--recursive --progress --stats -uhv"
	else
		rsyncParams="--remove-source-files --recursive --progress --stats -uhv"
	fi
	
	if [[ "$Checksum" == "true" ]]
	then
		rsyncParams="$rsyncParams -c"
	fi
	
	listExcludePrint
	excludes=$(listExclude $1)
	if [[ "$excludes" != "false" ]]
	then
		rsyncParams="$rsyncParams $excludes"
	fi
	
	if [[ "$PathInHost" == "" ]]
	then
		rsyncParams="$rsyncParams $MountPoint/ ${Hard[0]}/$PathOut/$DIRNOW/"
	else
		rsyncParams="$rsyncParams $MountPoint/$PathInHost/ ${Hard[0]}/$PathOut/$DIRNOW/"
	fi
	
	rsync $rsyncParams
	querySpace
	
	#Очистка переменных
	CLC=0
	for CL in ${Include[@]}
	do
		Include[$CLC]=""
		CLC=$((++CLC))
	done
	CLC=0
	for CL in ${Exclude[@]}
	do
		Exclude[$CLC]=""
		CLC=$((++CLC))
	done
	
	log "$cn Синхронизация завершена"
	
}

#Очистка
function startClear {
	logln "[$(date +"%Y.%m.%d %H:%M:%S")] Определяем каталог для удаления "
	MaxList=0
	MaxListName=0
	MaxListConfigName=0
	for startClear_cn in $(ls -1 $ConfigPath/)
	do
		source $ConfigPath/$startClear_cn
		if [[ "$Active" == "true" ]]
		then
			if [[ -d "${Hard[0]}/$PathOut" ]]
			then
				DList=$(ls -1 ${Hard[0]}/$PathOut/ | wc -l)
				if (( "$DList" > "$MaxList" ))
				then
					MaxList=$DList
					MaxListName=$PathOut
					MaxListConfigName=$startClear_cn
				fi
			fi
		fi
	done
	
	logln "[ok]\n"
	log "Удаляться будет: ${Hard[0]}/$MaxListName/$(ls -1t ${Hard[0]}/$MaxListName/ | tail -1)"
	if [[ "$Debug" == "false" ]]
	then
		rm -rf "${Hard[0]}/$MaxListName/$(ls -1t ${Hard[0]}/$MaxListName/ | tail -1)"
	fi
	
}

#Обработка данных
function jobConfig {
	cn="[$1]"
	if [[ $(testconfig $1) == *fail* ]]
	then
		log "$cn ошибка конфига"
		return
	fi
	
	log "$cn начало работы"
	logln "[$(date +"%Y.%m.%d %H:%M:%S")] $cn проверка на доступность "
	ping $IpAddr -c 3 > /tmp/pinglog
    RESULT=`cat /tmp/pinglog|grep 'error'`
	if [[ "$RESULT" == "" ]]
	then
		logln "\t\t[ok]\n"
	else
		logln "\t\t[failed]\n"
		log "$cn недоступен"
		return
	fi
	
	logln "[$(date +"%Y.%m.%d %H:%M:%S")] $cn проверка на доступность smb "
	smbclient -N -L $IpAddr &> /dev/null
	if [ $? -ne 0 ]
	then
		logln "\t[failed]\n"
		log "$cn недоступен"
		return
	else
		logln "\t[ok]\n"
	fi
	
	logln "[$(date +"%Y.%m.%d %H:%M:%S")] $cn монтирование"
	if [[ "$Authorization" == true ]]
	then
		mount -t cifs -o user="$UserLogin",pass="$UserPassword",iocharset=utf8,file_mode=0666,dir_mode=0666 "//$IpAddr/$DirMount" "$MountPoint/"
	else
		ULogin=""
		UPassword=""
		mount -t cifs -o user="$ULogin",pass="$UPassword",iocharset=utf8,file_mode=0666,dir_mode=0666 "//$IpAddr/$DirMount" "$MountPoint/"
	fi
	if [[ $(mount | grep "$MountPoint") == "" ]]
	then
		logln " ошибка монтирования [failed]\n"
		return
	else
		logln "\t\t\t[ok]\n"
	fi
	
	if [[ "$PathInHost" == "" ]]
	then
		IFS=' ' read -r -a array <<< $(du -sh $MountPoint)
	else
		IFS=' ' read -r -a array <<< $(du -sh $MountPoint/$PathInHost)
	fi
	
	startRSYNC $1
	logln "[$(date +"%Y.%m.%d %H:%M:%S")] $cn размонтирование"
	umount $MountPoint
	if [[ $(mount | grep "$MountPoint") == "" ]]
	then
		logln "\t\t\t[ok]\n"
	else
		logln "\t\t\t[failed]\n"
		return
	fi
	
	log "$cn завершён"
}

#Start
function main {
	log "Начало работы"
	if [[ ! -d /tmp/backuper ]]
	then
		mkdir /tmp/backuper
	fi
	cd /tmp/backuper
	querySpace
	if [[ "$NetworkUpDown" == true ]]
	then
		log "Поднимаем сетевой интерфейс"
		networkUP
		sleep $NetworkSleep
	fi
	for config in $(ls -1 $ConfigPath | grep ".cfg")
	do
		source $ConfigPath/$config
		IFS='.' read -r -a array <<< $config
		configName=${array[0]}
		if [[ $Active == false ]]
		then
			log "[$configName] \t\t\t\t[отключен]"
		else
			if [[ $Period != 0 ]]
			then
				if [[ ! -f $PeriodPath/$configName ]]
				then
					log "$configName\t[перидоческое выполнение каждые $Period дней][первый запуск]"
					configNextStart=$(date '+%Y.%m.%d' --date="(date) $Period day")
					jobConfig $configName
					log "[$configName] следующий запуск будет $configNextStart"
					echo $configNextStart > $PeriodPath/$configName
				else
					configPeriodDate=$(cat $PeriodPath/$configName)
					if [[ "$(date +"%Y.%m.%d")" > "$configPeriodDate" || "$(date +"%Y.%m.%d")" == "$configPeriodDate" ]]
					then
						log "[$configName] периодическое выполнение сегодня"
						jobConfig $configName
						echo $(date '+%Y.%m.%d' --date="(date) $Period day") > $PeriodPath/$configName
						log "[$configName] следующий запуск будет $(date '+%Y.%m.%d' --date="(date) $Period day")"
					else
						log "$configName\t[период запуска не сегодня]"
					fi
				fi
			else
				jobConfig $configName
			fi
		fi
	done
	if [[ "$NetworkUpDown" == true ]]
	then
		log "Опускаем сетевой интерфейс"
		networkDown
	fi
	
	querySpace
	startSyncHards
	
	log "Завершено"
	logln "\n"
}

#Проверка настроек
testsettings

if [[ "$1" == "" ]]
then
	help;
	exit
fi

while [[ -n "$1" ]]
do
	case "$1" in
		"-h") help;;
		"--help") help;;
		"--get-settings") getsettings;;
		"--set-network-up") NetworkOnToUp;;
		"--set-network-down") NetworkOffToUp;;
		"--mc") makeDefaultConfig;;
		"--add-config") addConfig;;
		"--list-config") listConfig;;
		*--remove-config=*) removeConfig $1 ;;
		"--read-log") readLog;;
		*--config-log=*) configLog $1;;
		"--config-log-error") configLogError;;
		"--config-log-failed") configLogFailed;;
		"--hard-info") hardinfo;;
		"--test") test;;
		"--start") main;;
		*) echo "Неизвестный параметр $1";;
	esac
	shift
done
