# ДЗ 2. Работа с программными рейдами с помощью mdadm

* добавить в Vagrantfile еще дисков
* собрать R0/R5/R10 на выбор
* создать GPT раздел и 5 партиций
* прописать собранный рейд в конф, чтобы рейд собирался при загрузке
* сломать/починить raid
* *доп. задание - Vagrantfile, который сразу собирает систему с подключенным рейдом
* **перенесети работающую систему с одним диском на RAID 1. Даунтайм на загрузку с нового диска предполагается. В качестве проверики принимается вывод команды lsblk до и после и описание хода решения (можно воспользовать утилитой Script).

Используется vagrant 2.2.7 и virtualbox 6.1.6
За основу берется Vagrantfile из репозитория(вставить ссыль)
Перед изменениями в конфигах запускаем виртуалку и делаем из нее бокс на случай, если что-то пойдет не так, и виртуалку будет проще пересоздавать, не тратя времени на переустановку начального набора пакетов.
 ```
 vagrant package mdadm --output mdadm.box
 vagrant box add mdadm.box --name mdadm
 ```

### Добавить в Vagrantfile еще дисков
Открываем Vagrantfile, находим секцию с объявлением дисков, добавляем  еще два диска, не забывая контроллировать запятые после скобок, названия файлов, дисков в системе и номера портов.
```
                :sata5 => {
                        :dfile => './sata5.vdi',
                        :size => 250,
                        :port => 5
                },
                :sata6 => {
                        :dfile => './sata6.vdi',
                        :size => 250,
                        :port => 6
                }
```
Запускаем виртуалку (vagrant up && vagrant ssh), смотрим диски в системе и видим, что 6 указанных в вагрантфайле дисков добавились отдельно от диска с раскатанной системой:
```
[vagrant@mdadm ~]$ lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda      8:0    0  250M  0 disk 
sdb      8:16   0  250M  0 disk 
sdc      8:32   0  250M  0 disk 
sdd      8:48   0  250M  0 disk 
sde      8:64   0  250M  0 disk 
sdf      8:80   0  250M  0 disk 
sdg      8:96   0   40G  0 disk 
└─sdg1   8:97   0   40G  0 part /
```

### Собрать R0/R5/R10 на выбор
Соберем RAID5 из 5 дисков(один запасной)
```
[vagrant@mdadm ~]$ sudo mdadm --create --verbose /dev/md0 -l 5 -n 5 /dev/sd[a-e]
mdadm: layout defaults to left-symmetric
mdadm: layout defaults to left-symmetric
mdadm: chunk size defaults to 512K
mdadm: size set to 253952K
mdadm: Defaulting to version 1.2 metadata
mdadm: array /dev/md0 started.
[vagrant@mdadm ~]$ lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
sda      8:0    0  250M  0 disk  
└─md0    9:0    0  992M  0 raid5 
sdb      8:16   0  250M  0 disk  
└─md0    9:0    0  992M  0 raid5 
sdc      8:32   0  250M  0 disk  
└─md0    9:0    0  992M  0 raid5 
sdd      8:48   0  250M  0 disk  
└─md0    9:0    0  992M  0 raid5 
sde      8:64   0  250M  0 disk  
└─md0    9:0    0  992M  0 raid5 
sdf      8:80   0  250M  0 disk  
sdg      8:96   0   40G  0 disk  
└─sdg1   8:97   0   40G  0 part  /
[vagrant@mdadm ~]$ sudo fdisk -l /dev/md0

Disk /dev/md0: 1040 MB, 1040187392 bytes, 2031616 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 524288 bytes / 2097152 bytes
```
### Создать GPT раздел и 5 партиций
Диск промаркировал как GPT вручную утилитой parted
Далее для создания разделов попытался написать bash-скрипт, который автоматом нарезает любое количество разделов на равные части, но выяснил, что баш не умеет нормально работать с дробными числами, расстроился и удалил, поэтому создаем по старинке:
```
[vagrant@mdadm ~]$ history
   ...
   66  sudo parted /dev/md0 mkpart primary ext4 0% 20%
   67  sudo parted /dev/md0 mkpart primary ext4 20% 40%
   68  sudo parted /dev/md0 mkpart primary ext4 40% 60%
   69  sudo parted /dev/md0 mkpart primary ext4 60% 80%
   70  sudo parted /dev/md0 mkpart primary ext4 80% 100%
   ...
   74  for i in $(seq 1 5); do sudo mkfs.ext4 /dev/md0p$i; done
```

Массив размечен:
```
[vagrant@mdadm ~]$ sudo gdisk -l /dev/md0
GPT fdisk (gdisk) version 0.8.10

Partition table scan:
  MBR: protective
  BSD: not present
  APM: not present
  GPT: present

Found valid GPT with protective MBR; using GPT.
Disk /dev/md0: 2031616 sectors, 992.0 MiB
Logical sector size: 512 bytes
Disk identifier (GUID): 6A2BA715-4957-4E45-917A-91E0FA0E0A1F
Partition table holds up to 128 entries
First usable sector is 34, last usable sector is 2031582
Partitions will be aligned on 2048-sector boundaries
Total free space is 8125 sectors (4.0 MiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            4096          405503   196.0 MiB   0700  primary
   2          405504          811007   198.0 MiB   0700  primary
   3          811008         1220607   200.0 MiB   0700  primary
   4         1220608         1626111   198.0 MiB   0700  primary
   5         1626112         2027519   196.0 MiB   0700  primary
```
Монтируем:
```
[vagrant@mdadm ~]$ sudo su -c 'for i in $(seq 1 5); do mkdir -p /raid/part$i ; mount /dev/md0p$i /raid/part$i; done; ls /raid/'
part1  part2  part3  part4  part5
```
### Прописать собранный рейд в конф, чтобы рейд собирался при загрузке
Работаем по методичке, но чтобы понять, что такое mdadm.conf, читаем
https://linux.die.net/man/5/mdadm.conf

Проверяем информацию рейда  
[root@mdadm ~/# mdadm --detail --scan --verbose

Создаем конфиг  
[root@mdadm /]# echo "DEVICE partitions" > /etc/mdadm.conf
[root@mdadm etc]#  mdadm --detail --scan --verbose | awk '/ARRAY/ {print}' >> /etc/mdadm.conf
В методичке указан путь /etc/mdadm/mdadm.conf, но /etc/mdadm.conf так же работает.

Перезагружаемся и видим, что рейд собрался, но ФС не смонтированы - забыли добавить их в fstab
> Никогда не трать 10 минут на ручную задачу, которую можно автоматизировать за 10 часов  

Генерим конфиг фстаб. Скрипт работает только если ФС были смонтированы ранее. У нас уже смонтированы.
```
lsblk -f | grep md0p | awk '{print $3" "$4" ext4 defaults 0 0"}' | sort | uniq >> /etc/fstab
[vagrant@mdadm ~]$ cat /etc/fstab

#
# /etc/fstab
# Created by anaconda on Sat Jun  1 17:13:31 2019
#
# Accessible filesystems, by reference, are maintained under '/dev/disk'
# See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info
#
UUID=8ac075e3-1124-4bb6-bef7-a6811bf8b870 /                       xfs     defaults        0 0
/swapfile none swap defaults 0 0
UUID="4a035d97-5115-4a09-9b60-bc9860b4fda8" /raid/part1 ext4 defaults 0 0
UUID="ffc8aa0f-50d7-4789-9dc5-e422fd3177b6" /raid/part2 ext4 defaults 0 0
UUID="48e0cc5b-ed5a-4613-b516-29f514ef2e7b" /raid/part3 ext4 defaults 0 0
UUID="98ae2606-10ef-4c14-bfad-4efb7835c2a2" /raid/part4 ext4 defaults 0 0
UUID="ef44fce1-cdde-4d13-91f4-d989458b2341" /raid/part5 ext4 defaults 0 0
```
### Сломать/починить RAID
"Ломаем" диск:  
```
[root@mdadm vagrant]# mdadm /dev/md0 --fail /dev/sdc
mdadm: set /dev/sdc faulty in /dev/md0
```
Смотрим, что получилось:
```
[root@mdadm vagrant]# cat /proc/mdstat 
Personalities : [raid6] [raid5] [raid4] 
md0 : active raid5 sdf[5] sde[3] sdb[0] sdd[2] sdc[1](F)
      1015808 blocks super 1.2 level 5, 512k chunk, algorithm 2 [5/4] [U_UUU]
      
unused devices: <none>
[root@mdadm vagrant]# mdadm -D /dev/md0
/dev/md0:
           Version : 1.2
     Creation Time : Sun May 17 20:36:15 2020
        Raid Level : raid5
        Array Size : 1015808 (992.00 MiB 1040.19 MB)
     Used Dev Size : 253952 (248.00 MiB 260.05 MB)
      Raid Devices : 5
     Total Devices : 5
       Persistence : Superblock is persistent

       Update Time : Tue May 19 07:56:40 2020
             State : clean, degraded 
    Active Devices : 4
   Working Devices : 4
    Failed Devices : 1
     Spare Devices : 0

            Layout : left-symmetric
        Chunk Size : 512K

Consistency Policy : resync

              Name : mdadm:0  (local to host mdadm)
              UUID : 803a1caa:ea531fca:9f52f5bd:b5148010
            Events : 20

    Number   Major   Minor   RaidDevice State
       0       8       16        0      active sync   /dev/sdb
       -       0        0        1      removed
       2       8       48        2      active sync   /dev/sdd
       3       8       64        3      active sync   /dev/sde
       5       8       80        4      active sync   /dev/sdf

       1       8       32        -      faulty   /dev/sdc
```
Удаляем сломанный диск:
```
[root@mdadm vagrant]# mdadm /dev/md0 --remove /dev/sdc
mdadm: hot removed /dev/sdc from /dev/md0
```
Добавляем вместо сломанного диска новый и смотрим, пошло ли восстановление:
```
[root@mdadm vagrant]# mdadm /dev/md0 --add /dev/sdg
mdadm: added /dev/sdg
[root@mdadm vagrant]# cat /proc/mdstat 
Personalities : [raid6] [raid5] [raid4] 
md0 : active raid5 sdg[6] sdf[5] sde[3] sdb[0] sdd[2]
      1015808 blocks super 1.2 level 5, 512k chunk, algorithm 2 [5/4] [U_UUU]
      [=======>.............]  recovery = 38.8% (98816/253952) finish=0.1min speed=19763K/sec
      
unused devices: <none>
[root@mdadm vagrant]#
```

### *Доп. задание - Vagrantfile, который сразу собирает систему с подключенным рейдом
Результирующий Vagrantfile лежит в [репозитории](https://github.com/Iruta-san/otus-linux/tree/master/02-mdadm)  
В скрипт копируем все наши ручные действия, адаптируя их под запуск с правами рута.

### **перенесети работающую систему с одним диском на RAID 1. Даунтайм на загрузку с нового диска предполагается. В качестве проверики принимается вывод команды lsblk до и после и описание хода решения (можно воспользовать утилитой Script).

Для выполнения задания использовался базовый бокс centos/7 с минимумом необходимых настроек.
Все файлы по заданию находятся в https://github.com/Iruta-san/otus-linux/tree/master/02-mdadm/system2raid

Заходим в директорию, делаем vagrant init и изменяем новый Vagrantfile под свои нужды.  
Получившийся файл с подробными комментариями по действиям лежит тут:  
https://github.com/Iruta-san/otus-linux/blob/master/02-mdadm/system2raid/Vagrantfile

Посмотреть весь процесс сборки можно скопировав файлы timefile, makingraid.script и выполнив
```
scriptreplay timefile makingraid.script -d5
```
Прошу простить за то, что не подумавши запись запустил перед ***vagrant up***, что заметно увеличило ее продолжительность. 

--------------
### Текстовое описание выполнения ###
Запускаем виртуалку, проверяем, что в системе два диска:
```
lsblk
NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
sda      8:0    0  40G  0 disk 
`-sda1   8:1    0  40G  0 part /
sdb      8:16   0  40G  0 disk 
```
Копируем на второй диск разметку разделов с первого:
```
sfdisk -d /dev/sda | sfdisk /dev/sdb
```
Создаем RAID1 с одним отсутствующим диском
```
mdadm --create /dev/md0 missing /dev/sdb1 -l1 -n2
```
Далее с помощью fdisk /dev/md0 вручную создаем таблицу разделов GPT, один раздел на все свободное пространство, затем форматируем файловую систему:
```
mkfs.ext4 /dev/md0p1
```
Монтируем ФС и переносим на нее все данные с корневой ФС с помощью rsync
```
mount /dev/md0p1 /mnt
rsync -axu / /mnt # -a - архивный режим, сохраняет права, владельцев
# -x - ограничиться только одной ФС, не копировать примонтированные внутри неё
# -u - не перезаписывать существующие и более новые файлы в точке назначения. Например, на случай, если запустили повторно
```

Монтируем псевдофайловые системы
```
mount --bind /proc /mnt/proc && \
mount --bind /dev /mnt/dev && \
mount --bind /sys /mnt/sys && \
mount --bind /run /mnt/run
```
И далее работаем с корнем нашей будущей системы на рейде
```
chroot /mnt
```
Внутри редактируем /etc/fstab, удаляя старую запись о корневой ФС руками или с помощью команды
```
sed -i 's/.*\s\/\s.*//g' /etc/fstab
```
И добавляем туда в качестве корня наш рейд
```
ls -l /dev/disk/by-uuid | grep md | awk '{print "UUID="$9" / ext4 defaults 0 0"}' >> /etc/fstab
cat /etc/fstab # не забываем проверить результат
```
Сохраняем конфигурацию рейда
```
mdadm --detail --scan > /etc/mdadm.conf 
```
Генерируем новый initramfs
```
mv /boot/initramfs-3.10.0-1127.el7.x86_64.img /boot/initramfs-3.10.0-1127.el7.x86_64.img.bak # Старый сразу не удаляем, а прячем
dracut /boot/initramfs-$(uname -r).img $(uname -r)
```
Утилита для сборки initrd у нас dracut версии 033, который не настроен собирать рейды по умолчанию.  
Источник: https://habr.com/ru/post/248073/ со ссылкой на http://man7.org/linux/man-pages/man7/dracut.cmdline.7.html

Передаем ядру опцию «rd.auto=1» явно через «GRUB», для этого, добавляем ее в «GRUB_CMDLINE_LINUX»:  
```
vi /etc/default/grub  
GRUB_CMDLINE_LINUX="no_timer_check console=tty0 console=ttyS0,115200n8 net.ifnames=0 biosdevname=0 elevator=noop crashkernel=auto rd.auto=1"
```
Был еще вариант использовать UUID массива напрямую с опцией ядра rd.md.uuid=, но виртуалка с такой настройкой повисала при загрузке.

Обновляем конфиг и ставим граб на новый диск
```
grub2-mkconfig -o /boot/grub2/grub.cfg && grub2-install /dev/sdb
```

Убеждаемся, что uuid md0 и опция «rd.auto=1» точно записались:
```
cat /boot/grub2/grub.cfg
```
Говорим selinux, что нам надо переразметить всю файловую систему
```
touch /.autorelabel
```
Теперь перезагружаемся и в консоли Virtualbox вручную выбираем загрузку со второго диска.  
После того, как система загрузится с нашего все еще неполноценного рейда, произойдет переразметка всех файлов для SELinux, после чего виртуалка автоматом перезагрузится, и надо будет вновь выбрать загрузку со второго диска вручную.  
После того, как это было сделано, и мы залогинились на виртуалку обратно, проверяем, что мы действительно загрузились с рейда
```
[vagrant@disk2raid ~]$ lsblk
NAME        MAJ:MIN RM SIZE RO TYPE  MOUNTPOINT
sda           8:0    0  40G  0 disk  
`-sda1        8:1    0  40G  0 part  
sdb           8:16   0  40G  0 disk  
`-sdb1        8:17   0  40G  0 part  
  `-md0       9:0    0  40G  0 raid1 
    `-md0p1 259:0    0  40G  0 md    /
```

Теперь необходимо добавить исходный диск в наш массив.
Для этого меняем тип раздела старого диска
```
sfdisk --id /dev/sda 1 fd
```
Добавляем его в рейд
```
mdadm --manage /dev/md0 --add /dev/sda1
```
Ждем восстановления/синхронизации
```
watch cat /proc/mdstat
```
На всякий случай переустановим GRUB2 на старый диск(по идее должно было хватить и исходно имеющегося)
```
grub2-install /dev/sda
```

И снова перезагружаем виртуалку, чтобы проверить, что система грузится с нашего теперь полноценного RAID1  
Проверяем диски:
```
[root@disk2raid vagrant]# lsblk
NAME    MAJ:MIN RM SIZE RO TYPE  MOUNTPOINT
sda       8:0    0  40G  0 disk  
`-sda1    8:1    0  40G  0 part  
  `-md0   9:0    0  40G  0 raid1 /
sdb       8:16   0  40G  0 disk  
`-sdb1    8:17   0  40G  0 part  
  `-md0   9:0    0  40G  0 raid1 /
  ```
  И на этом всё!