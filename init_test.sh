#! /bin/bash

#************************************************************* Служебные переменные

HOST=''
USERS_CSV_FILE_PATH=''
JMETER_DIR_PATH=''
JMETER_TEST_PLAN_PATH=''

SESSION_KEY=''
LOGINTOKEN=''

INI_FILE_MANDATORILY_PARAM_LIST="HOST;USERS_CSV_FILE_PATH;JMETER_DIR_PATH;ADMIN_MOODLE;PASSWORD_MOODLE;JMETER_TEST_PLAN_PATH"
LOGINTOKEN_HTML_PATTERN='(?<=<input type="hidden" name="logintoken" value=")([a-zA-Z0-9]+)'
SESSIONKEY_HTML_PATTERN='(?<=<input type="hidden" name="sesskey" value=")([a-zA-Z0-9]+)'
CONFIRM_HTML_PATTERN='(?<=<input type="hidden" name="confirm" value=")([A-Za-z0-9]+)'
DEL_USER_ID_HTML_PATTERN='(?<=\/user\/view\.php\?id=)([0-9]+)'
COURSE_ID_HTML_PATTERN='(?<=\/course\/view\.php\?id=)([0-9]+)(?=\"\s\stitle)'
ENROL_ID_HTML_PATTERN='(?<=<input type=\"hidden\" name=\"enrolid\" value=\")([0-9]+)'
DELETE_TOKEN_HTML_PATTERN='(?<=<input type=\"hidden\" name=\"delete\" value=\")([A-Za-z0-9]+)'

#************************************************************** Переменные пользователя

login=''
password=''
firstname=''
lastname=''
email=''
city=''

let user_object_number_salt=0
let users_counter_salt=0

#********************************************************************** Модули

function print_error () {
	echo $1
	echo 'Аварийный выход'
	exit 1
}

function get_value_from_ini () {
	value=$(grep -m 1 $1 config.ini | tr -d ' ' | cut -d '=' -f2)

	if [[ -z "${value}" ]]; then
		print_error 'В ini файле не задан $1'
	fi

	echo ${value}
}

#exec 2>/dev/null

#****************************************************** Проверка служебных файлов

if [[ ! -e ./config.ini ]]; then
        print_error 'Отсутствует конфигурационной файл'
fi

#*************************************************************** Проверка пакета curl

if ! curl -V >/dev/null; then
        print_error 'Отсутствует пакет curl'
fi

#********************************************************* Извлечение параметров из ini файла

mandatorily_arr=$(echo $INI_FILE_MANDATORILY_PARAM_LIST | tr ";" "\n")
for value in ${mandatorily_arr[@]}; do
	case $value in
		HOST)
			HOST=$(get_value_from_ini 'HOST')
		;;
		USERS_CSV_FILE_PATH)
			USERS_CSV_FILE_PATH=$(get_value_from_ini 'USERS_CSV_FILE_PATH')
		;;
		JMETER_DIR_PATH)
			JMETER_DIR_PATH=$(get_value_from_ini 'JMETER_DIR_PATH')
                ;;
		ADMIN_MOODLE)
			ADMIN_MOODLE=$(get_value_from_ini 'ADMIN_MOODLE')
		;;
		PASSWORD_MOODLE)
			PASSWORD_MOODLE=$(get_value_from_ini 'PASSWORD_MOODLE')
		;;
		JMETER_TEST_PLAN_PATH)
			JMETER_TEST_PLAN_PATH=$(get_value_from_ini 'JMETER_TEST_PLAN_PATH')
		;;
		*)
	esac
done

#********************************************************* Проверка существования файла с пользователями

if [[ ! -e ${USERS_CSV_FILE_PATH} ]]; then
        print_error 'Файл с пользователями не найден'
fi


#******************************************************************************* Работа с moodle
###### Создание папок для временных файлов
if ! mkdir ./temp; then
	print_error 'Не удалось создать временную папку'
fi

if ! mkdir ./temp/HTML_pages/; then
        print_error 'Не удалось создать временную папку'
fi


###### Вход на сайт

echo -e "Запуск процесса авторизации на сайте ${HOST}"

###### Проверка получения токена

LOGINTOKEN=$(curl -s -c ./temp/cookies -L http://${HOST}/login/index.php | grep -oP "${LOGINTOKEN_HTML_PATTERN}")
if [[ -z "${LOGINTOKEN}" ]]; then
	print_error 'Ошибка получения токена пользователя'
fi

###### Проверка получения сессии

SESSIONKEY=$(curl -s -X POST -b ./temp/cookies -L http://${HOST}/login/index.php -F "username=${ADMIN_MOODLE}" -F "password=${PASSWORD_MOODLE}" -F "logintoken=${LOGINTOKEN}" -c ./temp/cookies | grep -oP "${SESSIONKEY_HTML_PATTERN}")
if [[ -z "${SESSIONKEY}" ]]; then
	print_error 'Ошибка получения сессии пользователя'
fi

echo 'Процесс авторизации завершен'
echo 'Запуск процесса добавления пользователей на сайт'

while read LINE; do

###### Извлечение данных из CSV файла с пользователями

	login=$(echo -e "${LINE}" | cut -d ',' -f1)
        password=$(echo -e "${LINE}" | cut -d ',' -f2)
        firstname=$(echo -e "${LINE}" | cut -d ',' -f3)
        lastname=$(echo -e "${LINE}" | cut -d ',' -f4)
        email=$(echo -e "${LINE}" | cut -d ',' -f5)
        city=$(echo -e "${LINE}" | cut -d ',' -f6)

##### Добавление в общий список пользователей, находящийся в RAM

	declare -A "user_object_${user_object_number_salt}_salt=( \
		["firstname"]="${firstname}" \
		["lastname"]="${lastname}" \
		["email"]="${email}" \
		["login"]="${login}" \
		["password"]="${password}" \
		["city"]="${city}" \
	)"

	let users_counter_salt+=1
	let user_object_number_salt+=1

##### Добавление пользователя на сервер moodle

	curl -s -X POST -b ./temp/cookies -L http://${HOST}/user/editadvanced.php \
		-F "id=-1" \
		-F "course=1" \
		-F "mform_isexpanded_id_moodle_picture=1" \
		-F "sesskey=${SESSIONKEY}" \
		-F "_qf__user_editadvanced_form=1" \
		-F "mform_isexpanded_id_moodle=1" \
		-F "mform_isexpanded_id_moodle_additional_names=0" \
		-F "mform_isexpanded_id_moodle_interests=0" \
		-F "mform_isexpanded_id_moodle_optional=0" \
		-F "username=${login}" \
		-F "auth=manual" \
		-F "suspended=0" \
		-F "newpassword=${password}" \
		-F "preference_auth_forcepasswordchange=0" \
		-F "firstname=${firstname}" \
		-F "lastname=${lastname}" \
		-F "email=${email}" \
		-F "maildisplay=2" \
		-F "city=${city}" \
		-F "timezone=99" \
		-F "lang=ru" \
		-F "description_editor[text]=qwerty123" \
		-F "description_editor[format]=1" \
		-F "imagefile=803826758" \
		-F "interests=_qf__force_multiselect_submission" \
		-F "submitbutton=Создать пользователя" >/dev/null

	echo -e "${login} добавлен. Прошло ${SECONDS} сек."
done < ${USERS_CSV_FILE_PATH}

echo 'Процесс добавления пользователей завершен'

#**************************************** Создание базового курса

echo 'Процесс создания тестового курса начат'

########### Создание курса

curl -s -X POST -b ./temp/cookies -L http://${HOST}/course/edit.php \
	-F "returnto=0" \
	-F "returnurl=http://192.168.1.37/course/" \
	-F "mform_isexpanded_id_descriptionhdr=1" \
	-F "sesskey=${SESSIONKEY}" \
	-F "_qf__course_edit_form=1" \
	-F "mform_isexpanded_id_general=1" \
	-F "mform_isexpanded_id_courseformathdr=0" \
	-F "mform_isexpanded_id_appearancehdr=0" \
	-F "mform_isexpanded_id_filehdr=0" \
	-F "mform_isexpanded_id_completionhdr=0" \
	-F "mform_isexpanded_id_groups=0" \
	-F "mform_isexpanded_id_rolerenaming=0" \
	-F "mform_isexpanded_id_tagshdr=0" \
	-F "fullname=TestMoodleTest" \
	-F "shortname=TMT" \
	-F "category=3" \
	-F "visible=1" \
	-F "startdate[day]=1" \
	-F "startdate[month]=6" \
	-F "startdate[year]=2021" \
	-F "startdate[hour]=0" \
	-F "startdate[minute]=0" \
	-F "enddate[day]=1" \
	-F "enddate[month]=6" \
	-F "enddate[year]=2022" \
	-F "enddate[hour]=0" \
	-F "enddate[minute]=0" \
	-F "enddate[enabled]=1" \
	-F "summary_editor[text]=qwerty123" \
	-F "summary_editor[format]=1" \
	-F "summary_editor[itemid]=343745919" \
	-F "overviewfiles_filemanager=711674122" \
	-F "format=topics" \
	-F "numsections=5" \
	-F "hiddensections=0" \
	-F "coursedisplay=0" \
	-F "newsitems=5" \
	-F "showgrades=1" \
	-F "showreports=0" \
	-F "maxbytes=0" \
	-F "enablecompletion=1" \
	-F "groupmode=0" \
	-F "groupmodeforce=0" \
	-F "defaultgroupingid=0" \
	-F "tags=_qf__force_multiselect_submission" \
	-F "saveanddisplay=Сохранить и показать" > "./temp/HTML_pages/result_course_page.html"

####### Извлечение id курса

test_course_id=$(grep -oP "${COURSE_ID_HTML_PATTERN}" "./temp/HTML_pages/result_course_page.html")

###### Извлечение enrolid курса

enrol_id=$(grep -m 1 -oP "${ENROL_ID_HTML_PATTERN}" "./temp/HTML_pages/result_course_page.html")

echo 'Процесс создания тестового курса завершен'

#******************** Извлечение id пользователя

####### Получить результрующую страницу HTML по поиску имени и фамилии пользователя

declare -a users_id

for(( i=0;i<${users_counter_salt};i++ )); do
        full_name=$(eval echo "\${user_object_${i}_salt[firstname]} \${user_object_${i}_salt[lastname]}")
        curl -s -X POST -b ./temp/cookies -L http://${HOST}/admin/user.php \
                -F "sesskey=${SESSIONKEY}" \
                -F "_qf__user_add_filter_form=1" \
                -F "form_showmore_id_newfilter=0" \
                -F "mform_isexpanded_id_newfilte=1" \
                -F "realname_op=0" \
                -F "realname=${full_name}" \
                -F "lastname_op=0" \
                -F "firstname_op=0" \
                -F "username_op=0" \
                -F "email_op=0" \
                -F "city_op=0" \
                -F "country_op=0" \
                -F "courserole_rl=0" \
                -F "courserole_ct=0" \
                -F "systemrole=0" \
                -F "cohort_op=0" \
                -F "idnumber_op=0" \
                -F "institution_o=0" \
                -F "department_op=0" \
                -F "lastip_op=0" \
                -F "addfilter=Добавить фильтр" > "./temp/HTML_pages/result_${full_name}.html"


####### Извлечение id найденного пользователя из полученного файла HTML

        users_id[${i}]=$(grep -oP "${DEL_USER_ID_HTML_PATTERN}" "./temp/HTML_pages/result_${full_name}.html")

######### Сброс фильтра

        curl -s -X POST -b ./temp/cookies -L http://${HOST}/admin/user.php \
                -F "sesskey=${SESSIONKEY}" \
                -F "_qf__user_active_filter_form=1" \
                -F "mform_isexpanded_id_actfilterhdr=1" \
                -F "removeall=Удалить все фильтры" >/dev/null
done

#********************************* Добавление слушатилей в курс

echo 'Добавление пользователей в курс'

for i in "${!users_id[@]}"; do
	curl -s -X POST -b ./temp/cookies -L http://${HOST}/enrol/manual/ajax.php \
        -F "mform_showmore_main=0" \
        -F "id=${test_course_id}" \
        -F "action=enrol" \
        -F "enrolid=${enrol_id}" \
        -F "sesskey=${SESSIONKEY}" \
        -F "_qf__enrol_manual_enrol_users_form=1" \
        -F "mform_showmore_id_main=0" \
        -F "userlist[]=${users_id[$i]}" \
        -F "roletoassign=5" \
        -F "startdate=4" >/dev/null

	eval echo "Пользователь \${user_object_${i}_salt[login]} добавлен в курс."
done

#**************************************** Запуск JMeter

####### Узнаем сколько в данный момент загружено пользователей

current_users=$(cat ${USERS_CSV_FILE_PATH} | wc -l)

####### Запуск основной программы

echo -e "${JMETER_DIR_PATH} ${JMETER_TEST_PLAN_PATH} ${HOST} ${test_course_id} ${current_users} ${USERS_CSV_FILE_PATH}"

bash ${JMETER_DIR_PATH}/bin/jmeter -n -t ${JMETER_TEST_PLAN_PATH} -Jhost=${HOST} -Jcourseid=${test_course_id} -Jusers=${current_users} -Jusers_path=/home/andrey/test-moodle/users.csv -f -l results.jtl

#**************************************** Удаление пользователей

echo 'Запуск процесса удаления пользователей с сайта'

for i in "${!users_id[@]}"; do

###########  Извлечение confirm токена

	confirm_token=$(curl -s -b ./temp/cookies -L http://${HOST}/admin/user.php \
		-F "sort=name" \
		-F "dir=ASC" \
		-F "perpage=30" \
		-F "page=0" \
		-F "delete=${users_id[$i]}" \
		-F "sesskey=${SESSIONKEY}" | grep -oP "${CONFIRM_HTML_PATTERN}"
	)

########## Подтверждение удаления пользователя

	curl -s -X POST -b ./temp/cookies -L http://${HOST}/admin/user.php \
        	-F "sort=name" \
        	-F "dir=ASC" \
        	-F "perpage=30" \
        	-F "page=0" \
        	-F "delete=${users_id[$i]}" \
        	-F "sesskey=${SESSIONKEY}" \
		-F "confirm=${confirm_token}" >/dev/null

	eval echo -e "Пользователь \${user_object_${i}_salt[login]} удален. Прошло ${SECONDS} сек."
done

echo -e "Процесс удаления пользователей завершен"

#**************************************** Удаление тестового курса

echo "Удаление тестового курса"

######### Получение delete token

curl -s -b ./temp/cookies -L http://${HOST}/course/delete.php -F "id=${test_course_id}" > "./temp/HTML_pages/delete_course_page.html"

######## Извлечение delete token

delete_token=$(grep -oP "${DELETE_TOKEN_HTML_PATTERN}" "./temp/HTML_pages/delete_course_page.html")

######## Удаление тестового курса

curl -s -X POST -b ./temp/cookies -L http://${HOST}/course/delete.php \
	-F "sesskey=${SESSIONKEY}" \
	-F "delete=${delete_token}" \
	-F "id=${test_course_id}" >/dev/null

echo "Тестовый курс удален"

#**************************************** Удаление временной папки

rm -R ./temp
