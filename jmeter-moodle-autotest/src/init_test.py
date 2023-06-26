import requests
import os
import configparser
import csv
import logging
import sys
import subprocess

from dataclasses import dataclass
from xmlrpc.client import Boolean
from bs4 import BeautifulSoup

class App:

	def __init__(self) -> None:
		self.ini_path = "../config/config.ini"
		self.users = []
		self.course = None

		self.file_logger = logging.getLogger('file_logger')
		self.file_logger.setLevel(logging.DEBUG)
		file_handler = logging.FileHandler(r'../app.log', mode="w")
		formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
		file_handler.setFormatter(formatter)
		self.file_logger.addHandler(file_handler)

		self.stdout_logger = logging.getLogger('terminal_logger')
		self.stdout_logger.setLevel(logging.DEBUG)
		stdout_handler = logging.StreamHandler(sys.stdout)
		formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
		stdout_handler.setFormatter(formatter)
		self.stdout_logger.addHandler(stdout_handler)


	def run(self) -> Boolean:
		if not os.path.isfile(self.ini_path):
			self.stdout_logger.error("Невозможно обнаружить ini файл")
			self.file_logger.error("Невозможно обнаружить ini файл")
			return False

		self.config = configparser.ConfigParser()
		self.config.read(self.ini_path)

		if not self._checked_ini_validation():
			self.stdout_logger.error("Обнаружены ошибки в параметрах ini файла")
			self.file_logger.error("Обнаружены ошибки в параметрах ini файла")
			return False

		self.host = self.config["DEFAULT"]["HOST"]
		self.users_csv_path = self.config["DEFAULT"]["USERS_CSV_FILE_PATH"]
		self.jmeter_dir_path = self.config["DEFAULT"]["JMETER_DIR_PATH"]
		self.moodle_login = self.config["DEFAULT"]["ADMIN_MOODLE"]
		self.moodle_password = self.config["DEFAULT"]["PASSWORD_MOODLE"]
		self.jmeter_test_plan_path = self.config["DEFAULT"]["JMETER_TEST_PLAN_PATH"]

		self.moodle = Moodle(self.host)

		self.stdout_logger.info("Проверка доступности хоста...")
		if not self._checked_remote_srv_availablity():
			self.stdout_logger.error("Недоступен хост {0}".format(self.host))
			self.file_logger.error("Недоступен хост {0}".format(self.host))
			return False
		self.stdout_logger.info("Хост {0} доступен".format(self.host))
		self.file_logger.info("Хост {0} доступен".format(self.host))
		
		if not os.path.isfile(self.users_csv_path):
			self.stdout_logger.error("Отсутствует csv файл с пользователями")
			self.file_logger.error("Отсутствует csv файл с пользователями")
			return False

		self.stdout_logger.info("Запуск процесса авторизации на сайте {0}".format(self.host))
		self.file_logger.info("Запуск процесса авторизации на сайте {0}".format(self.host))
		self.moodle.log_in(self.moodle_login, self.moodle_password)
		self.stdout_logger.info("Процесс авторизации завершен")
		self.file_logger.info("Процесс авторизации завершен")

		with open(self.users_csv_path) as csv_users_file:
			fieldnames=["login", "password", "firstname", "lastname", "email", "city"]
			users_rows = csv.DictReader(csv_users_file, fieldnames=fieldnames, delimiter=',')
			for row in users_rows:
				self.users.append(User(
					row["login"],
					row["password"],
					row["firstname"],
					row["lastname"],
					row["email"],
					row["city"]
				))

		self.stdout_logger.info("Запуск процесса добавления пользователей на сайт")
		self.file_logger.info("Запуск процесса добавления пользователей на сайт")
		for idx, user in enumerate(self.users):
			self.users[idx] = self.moodle.add_user(user)
			self.stdout_logger.info("{0} добавлен".format(user.login))
		self.stdout_logger.info("Процесс добавления пользователей завершен")
		self.file_logger.info("Процесс добавления пользователей завершен")

		self.course = Course(
			"TestMoodleTest",
			"TMT",
			1
		)
		self.stdout_logger.info("Процесс создания тестового курса начат")
		self.file_logger.info("Процесс создания тестового курса начат")
		self.course = self.moodle.add_course(self.course)
		self.stdout_logger.info("Процесс создания тестового курса завершен")
		self.file_logger.info("Процесс создания тестового курса завершен")
		
		self.stdout_logger.info("Добавление пользователей в тестовый курс...")
		self.file_logger.info("Добавление пользователей в тестовый курс...")
		for _, user in enumerate(self.users):
			self.moodle.enroll_user(user, self.course)
			self.stdout_logger.info("{0} добавлен в тестовый курс".format(user.login))
		self.stdout_logger.info("Все пользователи добавлены в курс")
		self.file_logger.info("Все пользователи добавлены в курс")

		self.stdout_logger.info("Запуск основной нагрузочной программы...")
		self.file_logger.info("Запуск основной нагрузочной программы...")
		self._start_jmeter()
		self.stdout_logger.info("Нагрузочное тестирование завершено")
		self.file_logger.info("Нагрузочное тестирование завершено")

		self.stdout_logger.info("Запуск процесса удаления пользователей с сайта")
		self.file_logger.info("Запуск процесса удаления пользователей с сайта")
		for _, user in enumerate(self.users):
			self.moodle.del_user(user)
			self.stdout_logger.info("{0} удален".format(user.login))
		self.stdout_logger.info("Процесс удаления пользователей завершен")
		self.file_logger.info("Процесс удаления пользователей завершен")

		self.stdout_logger.info("Удаление тестового курса")
		self.file_logger.info("Удаление тестового курса")
		self.moodle.del_course(self.course)
		self.stdout_logger.info("Тестовый курс удален")
		self.file_logger.info("Тестовый курс удален")

		self.stdout_logger.info("Скрипт завершен успешно!")
		self.file_logger.info("Скрипт завершен успешно!")

		return True

	def _checked_ini_validation(self) -> Boolean:
		if not self.config.has_option(None, 'HOST'):
			return False
		
		if not self.config.has_option(None, 'USERS_CSV_FILE_PATH'):
			return False
		
		if not self.config.has_option(None, 'JMETER_DIR_PATH'):
			return False
		
		if not self.config.has_option(None, 'ADMIN_MOODLE'):
			return False
		
		if not self.config.has_option(None, 'PASSWORD_MOODLE'):
			return False

		if not self.config.has_option(None, 'JMETER_TEST_PLAN_PATH'):
			return False
		
		return True
		

	def _checked_remote_srv_availablity(self):
		response = os.system("ping -c 6 -i 0.5 {0} >>/dev/null".format(self.host))
		if response != 0:
			return False

		return True
	
	def _start_jmeter(self):
		result_jtl_file = "results.jtl"

		subprocess.call(["bash", "{0}/bin/jmeter".format(self.jmeter_dir_path),
			"-n", "-t", self.jmeter_test_plan_path, "-Jhost={0}".format(self.host),
			"-Jcourseid={0}".format(self.course.course_id),
			"-Jusers={0}".format(len(self.users)), "-Jusers_path={0}".format(self.users_csv_path),
			"-f", "-l", result_jtl_file
		])

		
@dataclass
class User:
	login : str
	password : str
	firstname : str
	lastname : str
	email : str
	city : str
	user_id : int = 0


@dataclass
class Course:
	full_name : str
	short_name : str
	course_category : int
	enroll_id : int = 0
	course_id : int = 0

class Moodle:

	def __init__(self, host) -> None:
		self.session = requests.Session()
		self.logintoken = None
		self.sessionkey = None
		self.host = host

	def log_in(self, moodle_login, moodle_password):
		resp = self.session.get("http://{0}/login/index.php".format(self.host))
		soup = BeautifulSoup(resp.content, 'lxml')
		self.logintoken = soup.find("input", {"name" : "logintoken"})['value']
		resp = self.session.post("http://{0}/login/index.php".format(self.host), data={
			'username': moodle_login,
			'password': moodle_password,
			'logintoken': self.logintoken
		})
		soup = BeautifulSoup(resp.content, 'lxml')
		self.sessionkey = soup.find("input", {"name" : "sesskey"})['value']

	def add_user(self, user) -> User:
		resp = self.session.post("http://{0}/user/editadvanced.php".format(self.host), allow_redirects=True,
			data={
				"id": -1,
				"course": 1,
				"mform_isexpanded_id_moodle_picture": 1,
				"sesskey": self.sessionkey,
				"_qf__user_editadvanced_form": 1, 
				"mform_isexpanded_id_moodle": 1, 
				"mform_isexpanded_id_moodle_additional_names": 0, 
				"mform_isexpanded_id_moodle_interests" :0, 
				"mform_isexpanded_id_moodle_optional": 0, 
				"username": user.login, 
				"auth": "manual", 
				"suspended": 0, 
				"newpassword": user.password, 
				"preference_auth_forcepasswordchange": 0, 
				"firstname": user.firstname, 
				"lastname": user.lastname, 
				"email": user.email, 
				"maildisplay": 2, 
				"city": user.city, 
				"timezone": 99, 
				"lang": "en", 
				"description_editor[text]": "qwerty123", 
				"description_editor[format]": 1, 
				"imagefile": 803826758,
				"interests": "_qf__force_multiselect_submission",
				"submitbutton": "Create user"
			}
		)
		soup = BeautifulSoup(resp.content, 'lxml')
		user_html_list = soup.select('a[href*="http://{0}/user/editadvanced.php?id="]'.format(self.host))
		user.user_id = user_html_list[-1]['href'].split(sep="=")[1].split(sep="&")[0]

		return user

	def add_course(self, course) -> Course:
		resp = self.session.post("http://{0}/course/edit.php".format(self.host), allow_redirects=True,
			data={
				"returnto": 0, 
				"returnurl": "http://{0}/course/".format(self.host), 
				"mform_isexpanded_id_descriptionhdr": 1, 
				"sesskey": self.sessionkey, 
				"_qf__course_edit_form": 1, 
				"mform_isexpanded_id_general": 1, 
				"mform_isexpanded_id_courseformathdr": 0, 
				"mform_isexpanded_id_appearancehdr": 0, 
				"mform_isexpanded_id_filehdr": 0, 
				"mform_isexpanded_id_completionhdr": 0, 
				"mform_isexpanded_id_groups": 0, 
				"mform_isexpanded_id_rolerenaming": 0, 
				"mform_isexpanded_id_tagshdr": 0, 
				"fullname": course.full_name, 
				"shortname": course.short_name, 
				"category": course.course_category, 
				"visible": 1, 
				"startdate[day]": 1, 
				"startdate[month]": 6, 
				"startdate[year]": 2021, 
				"startdate[hour]": 0, 
				"startdate[minute]": 0, 
				"enddate[day]": 1, 
				"enddate[month]": 6, 
				"enddate[year]": 2022, 
				"enddate[hour]": 0, 
				"enddate[minute]": 0, 
				"enddate[enabled]": 1, 
				"summary_editor[text]": "qwerty123", 
				"summary_editor[format]": 1, 
				"summary_editor[itemid]": 343745919, 
				"overviewfiles_filemanager": 711674122, 
				"format": "topics", 
				"numsections": 5, 
				"hiddensections": 0, 
				"coursedisplay": 0, 
				"newsitems": 5, 
				"showgrades": 1, 
				"showreports": 0, 
				"maxbytes": 0, 
				"enablecompletion": 1, 
				"groupmode": 0, 
				"groupmodeforce": 0, 
				"defaultgroupingid": 0, 
				"tags": "_qf__force_multiselect_submission", 
				"saveanddisplay": "Save and display"
			}
		)
		soup = BeautifulSoup(resp.content, 'lxml')
		course_html_list = soup.select('a[href*="http://{0}/course/view.php?id="]'.format(self.host))
		course.course_id = course_html_list[-1]['href'].split(sep="=")[1]
		course.enroll_id = soup.find("input", {"name" : "enrolid"})['value']

		return course


	def enroll_user(self, user, course):
		self.session.post("http://{0}/enrol/manual/ajax.php".format(self.host), allow_redirects=True,
			data={
				"mform_showmore_main": 0, 
				"id": course.course_id, 
				"action": "enrol", 
				"enrolid": course.enroll_id, 
				"sesskey": self.sessionkey, 
				"_qf__enrol_manual_enrol_users_form": 1, 
				"mform_showmore_id_main": 0, 
				"userlist[]": user.user_id, 
				"roletoassign": 5, 
				"startdate": 4
			}
		)

	def del_user(self, user):
		resp = self.session.get("http://{0}/admin/user.php".format(self.host), allow_redirects=True,
			params={
				"sort": "name", 
				"dir": "ASC", 
				"perpage": 30,
				"page": 0, 
				"delete": user.user_id, 
				"sesskey": self.sessionkey
			}
		)
		soup = BeautifulSoup(resp.content, 'lxml')
		confirm_token = soup.find("input", {"name" : "confirm"})['value']
		self.session.post("http://{0}/admin/user.php".format(self.host), allow_redirects=True,
			data={
				"sort": "name",
				"dir": "ASC", 
				"perpage": 30, 
				"page": 0, 
				"delete": user.user_id,
				"sesskey": self.sessionkey, 
				"confirm": confirm_token
			}
		)

	def del_course(self, course):
		resp = self.session.get("http://{0}/course/delete.php".format(self.host), allow_redirects=True,
			params={
				"id": course.course_id
			}
		)
		soup = BeautifulSoup(resp.content, 'lxml')
		delete_token = soup.find("input", {"name" : "delete"})['value']
		self.session.post("http://{0}/course/delete.php".format(self.host), allow_redirects=True,
			data={
				"sesskey": self.sessionkey, 
				"delete": delete_token,
				"id": course.course_id
			}
		)


if __name__ == "__main__":
	app = App()
	app.run()