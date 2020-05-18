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

Генерим конфиг фстаб. Здесь мне помогает решение монтировать ФС в директории с соответствующими номерами на конце)))  
```
sudo blkid | grep md0p | awk '{print $2" "$1}' | sed 's/.$//' | sed 's/\/dev\/md0p/\/raid\/part/g' | sed 's/$/ ext4 defaults 0 0/g' | sudo tee -a /etc/fstab
UUID="4a035d97-5115-4a09-9b60-bc9860b4fda8" /raid/part1 ext4 defaults 0 0
UUID="ffc8aa0f-50d7-4789-9dc5-e422fd3177b6" /raid/part2 ext4 defaults 0 0
UUID="48e0cc5b-ed5a-4613-b516-29f514ef2e7b" /raid/part3 ext4 defaults 0 0
UUID="98ae2606-10ef-4c14-bfad-4efb7835c2a2" /raid/part4 ext4 defaults 0 0
UUID="ef44fce1-cdde-4d13-91f4-d989458b2341" /raid/part5 ext4 defaults 0 0
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
