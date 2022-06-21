#!/bin/bash


tmpFile="/tmp/tmpEnumAD"
touch $tmpFile
echo '' > $tmpFile

function ctrlC(){
	echo -e "\n\n[!]Saliendo...\n"
	exitFunc 1
}

function exitFunc(){
	rm $tmpFile &>/dev/null
	tput cnorm
	exit "$1"
}

trap ctrlC INT
tput civis 

function openPort(){
	timeout 1 bash -c "echo '' > /dev/tcp/$ip/$1" &>/dev/null || { echo -e "\n[!]El puerto $1 esta cerrado"; return 1;}
	return 0
}

function enumGroups(){

	openPort 139 || return 1

	echo -e "\n[+]Grupos:"

	if [[ -z $username ]]; then
		rpcclient -U '' -N $ip -c "enumdomgroups" | grep -oP '\[.*?\]' | grep -v "0x" | tr -d '[]'
	else
		rpcclient -U "$username%$password" $ip -c "enumdomgroups" | grep -oP '\[.*?\]' | grep -v "0x" | tr -d '[]'
	fi

	if [[ $? -ne 0 ]]; then
		echo -e '\n[!]No se puede acceder por rpc'
		return 1
	fi
	return 0
}

function enumUsers(){
	
	openPort 139 || return 1

	if [[ -z $username ]]; then
		rpcclient -U '' -N "$ip" -c "querydispinfo" > $tmpFile
	else
		rpcclient -U "$username%$password" "$ip" -c "querydispinfo" > $tmpFile
		echo "$username%$password"
	fi

	if [[ $? -ne 0 ]]; then
		echo -e '\n[!]No se puede acceder por rpc'
		return 1
	fi
	
	if $1; then
		rm "usersAD.txt" &>/dev/null
		touch "usersAD.txt" &>/dev/null
	fi
	echo -e "\n[+]Users:\n"

	while read -r line; do
		echo "$line" |  cut -d " " -f8 | awk -F '\t' '{print $1}'
		if $1; then
			echo "$line" |  cut -d " " -f8 | awk -F '\t' '{print $1}' >> "usersAD.txt"
		fi
		aux=$(echo "$line" | awk -F: '{print $7}')
		echo -e "\tDescription: $aux"
	done < "$tmpFile"


	echo '' > $tmpFile
	return 0
}

function enumMembers(){
	
	local group="$1"
	if [[ -z $username ]]; then
		local groups=(`rpcclient -U '' -N $ip -c "enumdomgroups" | grep -oP '\[.*?\]' | grep -A 1 -i "$group" | tr -d '[]'`)
	else
		local groups=(`rpcclient -U "$username%$password" $ip -c "enumdomgroups" | grep -oP '\[.*?\]' | grep -A 1 -i "$group" | tr -d '[]'`)
	fi

	if [[ $? -ne 0 ]]; then
		echo -e '\n[!]No se puede acceder por rpc'
		return 1
	elif [[ ${#groups[@]} -eq 0 ]]; then
		echo -e "\n[!]El grupo $group no existe"; return 1
	fi

	if [[ -z $username ]]; then
		local members=(`rpcclient -U '' -N $ip -c "querygroupmem ${groups[2]}" | cut -d " " -f1 | grep -oP "\[.*?\]" | tr -d "[]"`)
	else
		local members=(`rpcclient -U "$username%$password" $ip -c "querygroupmem ${groups[2]}" | cut -d " " -f1 | grep -oP "\[.*?\]" | tr -d "[]"`)
	fi

	echo -e "\n[+]Usuarios del grupo $group:"

	for (( i = 0; i < ${#members[@]}; i++ )); do
		if [[ -z $username ]]; then
			rpcclient -U '' -N $ip -c "queryuser ${members[$i]}" | grep -i "User Name" | cut -d ':' -f2 >> $tmpFile &
		else
			rpcclient -U "$username%$password" $ip -c "queryuser ${members[$i]}" | grep -i "User Name" | cut -d ':' -f2 >> $tmpFile &
		fi
	done; wait

	 
	cat "$tmpFile" | tr -d "\t" 
	echo '' > $tmpFile
	return 0
}

function enumGroupMembers(){
	if [[ -z $1  ]]; then
		echo -e "[!]\nSe necesita pasar un grupo"
	fi

	local groups
	groups="$1"
	openPort 139

	if [[ $? -ne 0 ]]; then
	   	echo -e "\n[!]El RPC esta cerrado"; return 1
	fi   

	echo "$groups" | tr ',' '\n' > $tmpFile
	while read -r line; do
		enumMembers "$line"
	done < "$tmpFile"
	
	echo '' > $tmpFile
	return 0
}

function enumSmb(){


	openPort 445 || return 1

	echo -e "\n[+]Shares:\n"
	if [[ -z $username ]]; then
		smbmap -H "$ip" -u 'guest'
	else
		smbmap -H "$ip" -u "$username" -p "$password"
	fi

	return 0
}

function smbActive(){

	openPort 445 || return 1

	local share output
	share="$1"
	if [[ -z "$username" ]]; then
		output=$(smbclient "//$ip/$share" -N -c ls)
	else
		output=$(smbclient "//$ip/$share" -U "$username%$password" -c ls)
	fi
	
	if [[ $(echo "$output" | grep -c "NT_STATUS_ACCESS_DENIED") -eq 1 ]]; then
		echo -e "\n[!]Acceso denegado a $share";return 1
	elif [[ $(echo "$output" | grep -c "NT_STATUS_BAD_NETWORK_NAME") -eq 1  ]]; then
		echo -e "\n[!]Share $share no existe";return 1
	fi

	return 0
}

function dowloadShare(){

	local share code
	share="$1"
	smbActive "$share" || return 1

	if ! $code ;then
		return "$code"
	fi

	echo -e "\n[*]Descargando archivos de $share\n"
	mkdir "$share""Share" &>/dev/null
	(
	cd "$share""Share"

	if [[ -z "$username" ]]; then
		smbclient "//$ip/$share"  -N -c "prompt off;recurse ON;mget *" &>/dev/null
	else
		smbclient "//$ip/$share"  -U "$username%$password" -c "prompt off;recurse ON;mget *" &>/dev/null
	fi
	)
	
	echo -e "\n[+]Descarga completada"
}

function enumWritePermision(){

	local share output user
	share="$1"
	smbActive "$share" || return 1

	echo -e "\n[*]Enumerando permisos de escritura\n"


	if [[ -z $username ]]; then
		user="guest"
	else
		user=$username
	fi

	mkdir mount
	mount -t cifs "//$ip/$share" ./mount -o "username=$user,password=$password,rw" || { echo "Error creando la montura"; return 1; }
	(
	cd mount || { echo "Error"; return 1; }
	find . -type d | while read -r directory; do 
		touch "${directory}/prove" 2>/dev/null && echo "${directory} - Write file" && rm "${directory}/prove";
		mkdir "${directory}/prove" 2>/dev/null && echo "${directory} - Write dir" && rmdir "${directory}/prove";
	done > $tmpFile 2>/dev/null
	)
	umount ./mount
	rmdir ./mount &>/dev/null
	if [[ ! -s $tmpFile ]] ; then
		echo -e "[-]No se tienen permisos de escritura"
	else
		cat $tmpFile
	fi

	return 0
}

function enumShare(){


	local share output
	share="$1"
	
	smbActive "$share" || return 1

	echo
	if [[ -z "$username" ]]; then
		smbclient "//$ip/$share/" -N -c "recurse;ls" | sed '$ d'
	else
		smbclient "//$ip/$share/" -U "$username%$password" -c "recurse;ls" | sed '$ d'
	fi

	return 0
}

function enumLdap(){

	openPort 389
	echo
	if [[ -z $domain ]];then
		echo "[!]Se necesita especificar el dominio"
		return 1
	fi

	ldapdomaindump -u "$domain\\$username" -p "$password" "$ip" -o "ldapDomainDump"

	return 0
}


function enumUsersKerberos(){

	if [[ -z $domain ]];then
		echo "[!]Se necesita especificar el dominio"
		return 1
	fi

	kerbrute  userenum -d "$domain" -o "validUsers.txt" -t 20 --dc "$ip" "$wordlist"

	return 0
}

function reconBasic(){
	enumUsers
	enumSmb
}

function help(){

	echo -e "\n[+]Usage: $0 [Options] IP\n"
	echo -e "\t-u \t\t\tUser"
	echo -e "\t-p \t\t\tPassword"
	echo -e "\t-d \t\t\tDomain"
	echo -e "\t--rpc \t\t\tEnum users with descriptions"
	echo -e "\t--rpcg \t\t\tEnum users with descriptions and save the users in a file"
	echo -e "\t--groups \t\tEnum groups"
	echo -e "\t--members [Group] \tEnum members of a group"
	echo -e "\t--shares \t\tEnum shares"
	echo -e "\t-S [Share] \t\tEnum the share"
	echo -e "\t-P [Share] \t\tEnum for writing permision in all directories in the share"
	echo -e "\t-D [Share] \t\tDowload the share " 
	echo -e "\t-B \t\t\tEnum users and shares (default)"
	echo -e "\t-L \t\t\tEnum LDAP in Active Directory"
	echo -e "\t-E [Wordlist]\t\tEnum Users"
	echo -e "\t-W [File] \t\tCreate a wordlist from a file with names"

	exitFunc 0
}


if [[ $# -eq 0  ]]; then
	help
fi


doEnumUsers=false
saveOut=false
doEnumGroups=false
doEnumGroupMembers=false
doEnumSmb=false
doEnumShare=false
doEnumWritePermision=false
doReconBasic=false
doDowloadShare=false
doLdapEnum=false
doEnumUsersKerberos=false
wordlist=""
share=""

while [[ -n $1 ]]; do
	
	if [[ $1 == "-u" ]]; then
		username="$2"
	elif [[ $1 == "-p" ]]; then
		password="$2" 
	elif [[ $1 == "-d" ]]; then
		domain="$2"
	elif [[ $1 == "-o" ]]; then
		output="$2"
	elif [[ $1 == "--rpc" ]]; then
		 doEnumUsers=true
	elif [[ $1 == "--rpcg" ]]; then
		doEnumUsers=true
		saveOut=true
	elif [[ $1 == "--groups" ]]; then
		doEnumGroups=true
	elif [[ $1 == "--members" ]]; then
		doEnumGroupMembers=true
	elif [[ $1 == "--shares" ]]; then
		doEnumSmb=true
	elif [[ $1 == "-S" ]]; then
		doEnumShare=true
		share="$2"
	elif [[ $1 == "-P" ]]; then
		doEnumWritePermision=true
		share="$2"
	elif [[ $1 == "-B" ]]; then
		doReconBasic=true
	elif [[ $1 == "-D" ]]; then
		doDowloadShare=true
		share="$2"
	elif [[ $1 == "-L" ]]; then
		doLdapEnum=true
	elif [[ $1 == "-E" ]]; then
		doEnumUsersKerberos=true
		wordlist="$2"
	elif [[ $1 == "-W" ]]; then
		python3 createWordlist.py "$2" 2>/dev/null || { echo -e "\n[!]The file createWordlist.py doesn't exist" || exitFunc "1" ; }
	elif [[ $1 == "-h" || $1 == "--help" ]] ;then
		help
	fi

	ip="$1"
	shift
done



if $doEnumUsers; then
	enumUsers "$saveOut"
fi
if $doEnumGroups; then
	enumGroups
fi
if $doEnumGroupMembers; then
	enumMembers
fi
if $doEnumSmb; then
	enumSmb
fi
if $doEnumShare; then
	enumShare "$share"
fi
if $doEnumWritePermision; then
	enumWritePermision "$share"
fi
if $doReconBasic; then
	reconBasic
fi
if $doDowloadShare; then
	dowloadShare "$share"
fi
if $doLdapEnum; then
	enumLdap
fi

if $doEnumUsersKerberos; then
	enumUsersKerberos 
fi



exitFunc 0




