# ДЗ 1. 

## 1. Обновление ядра из репозитория
За основу берем Vagrantfile из репозитория https://github.com/dmitry-lyutenko/manual_kernel_update

Результирующие файлы находятся в https://github.com/Iruta-san/otus-linux/tree/master/01-box-with-updated-kernel

Клонируем репозиторий, переходим в директорию, запускаем виртуальную машину
``` 
vagrant up
vagrant ssh 
```
### Обновление ядра
Подключаем репозиторий, откуда возьмем необходимую версию ядра.
```
sudo yum install -y http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
```
Ставим последнюю версию ядра:
```
sudo yum --enablerepo elrepo-kernel install kernel-ml -y
```

Обновляем конфигурацию загрузчика:
```
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

Перезагружаем виртуальную машину:
```
sudo reboot
```
После перезагрузки виртуальной машины заходим в нее и проверяем версию ядра:
```
uname -r
```
## Создание и заливка бокса с помощью Packer

Изменяем файл packer/centos.json под исходный образ.
```
 "artifact_description": "CentOS 7.8 updated kernel",
    "artifact_version": "7.8.2003",
    "image_name": "centos-7-8-5"
```
На момент выполнения ДЗ образ Centos 7.7.1908 перестал быть доступен, используем Centos 7.8.2003:
```
"iso_url": "http://mirror.yandex.ru/centos/7.8.2003/isos/x86_64/CentOS-7-x86_64-Minimal-2003.iso",
      "iso_checksum": "659691c28a0e672558b003d223f83938f254b39875ee7559d1a4a14c79173193",
      "iso_checksum_type": "sha256",
```
Скрипты packer изменяем в соответствии с выполненными вручную действиями.

В stage-1-kernel-update.sh убираем строчки, удаляющие ядро
```
# Remove older kernels (Only for demo! Not Production!)
rm -f /boot/*3.10*
```
В stage-2-clean.sh отключаем переключение дефолтной загрузки на старое ядро
```
#grub2-set-default 1
#echo "###   Hi from secone stage" >> /boot/grub2/grub.cfg
```
Запускаем сборку
```
packer build centos.json 
```
Получили файл с образом. Импортируем его в vagrant, проверяем в соответствии с мануалом и заливаем в cloud
```
vagrant cloud auth login
vagrant cloud publish --release Iruta-san/centos-7-8-5 1.0 virtualbox centos-7.8.2003-kernel-5-x86_64-Minimal.box
```
Прописываем в  Vagrantfile использование свежезалитого образа
```
Vagrant.configure("2") do |config|
  config.vm.box = "Iruta-san/centos-7-8-5"
  config.vm.box_version = "1.0"
end
```  

## 2. **Обновление ядра из исходных кодов с подключением общей с хостом директории

Используем за основу материалы из репозитория https://github.com/dmitry-lyutenko/manual_kernel_update

Результаты лежат в https://github.com/Iruta-san/otus-linux/tree/master/01-box-with-updated-kernel/from_src

Используемая версия виртуалбокс - 6.1.6, будем ставить ядро версии 5.4.41
Версия вагранта - 2.2.7
Для работы с шаренными папками потребуется плагин, ставим его на хосте командой
```
vagrant plugin install vagrant-vbguest
```
Как вариант, можно воспользоваться монтированием из основного интерфейса виртуалбокс, но это требует добавления дополнительных устройств в вагрантфайл, поэтому научиться работать с плагином предпочтительнее

Клонируем репозиторий к себе, заходим в папку, запускаем виртуалку

В виртуалке качаем исходные коды ядра:
```
cd /usr/src/
sudo su
curl -O https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.4.41.tar.xz
tar xvf linux-5.4.41.tar.xz
cd linux-5.4.41
```

Устанавливаем пакеты, требуемые для компиляции
```
yum groupinstall -y "Development Tools"
yum install -y ncurses-devel openssl-devel bc elfutils-libelf-devel
```
Конфигурируем на основе конфигурации старого ядра:
```
yes "" | make oldconfig
```
И компилируем
```
make -j4
```
После компиляции устанавливаем модули и ядро
```
make modules_install install
make clean 
```

В конце будут скомпилированы модули ядра для гостевых дополнений, выдает ошибку об отсутствии X-сервера, игнорируем.

Проверяем нужные модули:
```
[vagrant@kernel-update ~]$ lsmod | grep vbox
vboxvideo              45056  1 
ttm                   118784  1 vboxvideo
drm_kms_helper        204800  1 vboxvideo
drm                   593920  4 drm_kms_helper,vboxvideo,ttm
vboxguest             376832  1 
``` 
Удаляем старое ядро, обновляем конфиг загрузчика и выключаемся
```
rm -rf /boot/*3.10*
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-set-default 0
poweroff
```

После выключения виртуалки вновь поднимаем ее с vagrant up, проверяем версию ядра с uname -r, проверяем, на месте ли все модули (```lsmod | grep vbox```), и если все ок - меняем вагрантфайл для работы с шаренными папками. 
Я создал для этого отдельную папку, чтобы не тащить в виртуалку весь мусор с хоста.
```
config.vm.synced_folder "shared", "/vagrant", type:"virtualbox", create: true
```
Далее делаем ```vagrant reload``` и проверяем работу шары.

### Создание вагрант-бокса
Есть два пути: packer и vagrant package
По причине того, что ДЗ выполняется в nested виртуалках, и компиляция ядра занимает очень много времени, я воспользовался другим способом сборки бокса из уже настроенной виртуалки: ```vagrant package```

Тем не менее, файлы для сборки бокса с помощью ```packer``` так же находятся в репозитории, в директории **from_src/packer**

Сперва выполним на виртуалке скрипт по очистке виртуалки, видоизмененный под наши нужды. Для этого положим его в общую директорию на хосте:
```
cp packer/scripts/stage-2-clean.sh shared
```
ОБращаем внимание на секцию **# Install vagrant default key**. Если виртуалкой планируем пользоваться дальше, необходимо будет в Vagrantfile добавить опцию с указанием собственного ключа, либо удалить дефолтный ssh-ключ, чтобы при запуске он сгенерировался и установился заново.
Для этого смотрим, где лежит старый ключ:
```
$ vagrant ssh-config
Host kernel-update
  HostName 127.0.0.1
  User vagrant
  Port 2222
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile /home/user/manual_kernel_update/.vagrant/machines/kernel-update/virtualbox/private_key
  IdentitiesOnly yes
  LogLevel FATAL

```
Когда всё готово, пакуем виртуалку в новый бокс и заливаем его в vagrant cloud:
```
vagrant package --output centos7_5.4.11.src.vbguest.box
vagrant cloud auth login
vagrant cloud publish --release Iruta-san/centos-7_5.4.41 1.1 \ virtualbox centos7_5.4.11.src.vbguest.box
```
Результирующий Vagrantfile, использующий свежезалитый бокс лежит [в репозитории](https://github.com/Iruta-san/otus-linux/blob/master/01-box-with-updated-kernel/from_src/Vagrantfile)