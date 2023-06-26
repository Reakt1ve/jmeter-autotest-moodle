import sys
import csv

if __name__ == "__main__":
	try:
		count_users = int(sys.argv[1])
	except ValueError:
		print("В качестве аргумента передано не числовое значение")
		exit()
	except IndexError:
		print("Передан пустой аргумент")
		exit()

	if count_users < 0:
		print("Невозможно сгенерировать отрицательное кол-во пользователей")
		exit()

	default_city = "Moscow"
	default_password = "123qweASD!@#"

	with open('users.csv', 'w') as csvfile:
		writer = csv.writer(csvfile, delimiter=",")
		for idx in range(count_users):
			writer.writerow(["generated_user_login_{0}".format(idx),
				default_password,"generated_user_firstname_{0}".format(idx),
				"generated_user_lastname_{0}".format(idx),
				"generated_user_email_{0}@mail.com".format(idx), default_city
			])
