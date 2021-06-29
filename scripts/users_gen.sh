#! /bin/bash

let salt=0
OUTPUTFILE_PATH='./users_new.csv'
DEFAULT_PASSWORD='123qweASD!@#'
DEFAULT_CITY='Moscow'

if [[ -z $1 ]]; then
	echo "Неверные входные параметры"
	echo "Аварийный выход"
	exit 1
fi

USERS_SIZE=$1

>${OUTPUTFILE_PATH}

for (( i=0;i<${USERS_SIZE};i++ )); do
	echo -e "generated_user_login_${salt},${DEFAULT_PASSWORD},generated_user_firstname_${salt},generated_user_lastname_${salt},generated_user_email_${salt}@mail.com,${DEFAULT_CITY}" >> ${OUTPUTFILE_PATH}
	let salt+=1
done
