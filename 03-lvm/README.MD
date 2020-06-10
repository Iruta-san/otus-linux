# ДЗ 3: LVM #
на имеющемся образе 
/dev/mapper/VolGroup00-LogVol00 38G 738M 37G 2% /

* уменьшить том под / до 8G  
* выделить том под /home  
* выделить том под /var  
* /var - сделать в mirror  
* /home - сделать том для снэпшотов
* прописать монтирование в fstab
* попробовать с разными опциями и разными файловыми системами ( на выбор)
	- сгенерить файлы в /home/
	- снять снэпшот
	- удалить часть файлов
	- восстановится со снэпшота
	- залоггировать работу можно с помощью утилиты script

* *на нашей куче дисков попробовать поставить btrfs/zfs - с кешем, снэпшотами - разметить здесь каталог /opt

Используется стенд из репозитория https://gitlab.com/otus_linux/stands-03-lvm
Лог работы с консолью лежит в файле typescript, хотя, кажется, туда попало не всё.

После загрузки стенда проверяем, с чем имеем дело
```
$ lsblk
NAME                    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda                       8:0    0   40G  0 disk
├─sda1                    8:1    0    1M  0 part
├─sda2                    8:2    0    1G  0 part /boot
└─sda3                    8:3    0   39G  0 part
  ├─VolGroup00-LogVol00 253:0    0 37.5G  0 lvm  /
  └─VolGroup00-LogVol01 253:1    0  1.5G  0 lvm  [SWAP]
sdb                       8:16   0   10G  0 disk
sdc                       8:32   0    2G  0 disk
sdd                       8:48   0    1G  0 disk
sde                       8:64   0    1G  0 disk
# pvdisplay
  --- Physical volume ---
  PV Name               /dev/sda3
  VG Name               VolGroup00
  PV Size               <39.00 GiB / not usable 30.00 MiB
  Allocatable           yes (but full)
  PE Size               32.00 MiB
  Total PE              1247
  Free PE               0
  Allocated PE          1247
  PV UUID               vrrtbx-g480-HcJI-5wLn-4aOf-Olld-rC03AY

# lvdisplay
  --- Logical volume ---
  LV Path                /dev/VolGroup00/LogVol00
  LV Name                LogVol00
  VG Name                VolGroup00
  LV UUID                j6b8IV-KEw3-7bTw-Oqy8-1Ud3-juFC-SJBg12
  LV Write Access        read/write
  LV Creation host, time localhost.localdomain, 2018-05-12 18:50:24 +0000
  LV Status              available
  # open                 1
  LV Size                <37.47 GiB
  Current LE             1199
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     8192
  Block device           253:0

  --- Logical volume ---
  LV Path                /dev/VolGroup00/LogVol01
  LV Name                LogVol01
  VG Name                VolGroup00
  LV UUID                IAjIC6-ScnM-tvH6-7BTy-TN31-hd82-bgDSzd
  LV Write Access        read/write
  LV Creation host, time localhost.localdomain, 2018-05-12 18:50:25 +0000
  LV Status              available
  # open                 2
  LV Size                1.50 GiB
  Current LE             48
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     8192
  Block device           253:1
```

### Уменьшить том под / до 8G
Делаем команду  
lvresize --resizefs --size 8G /dev/VolGroup00/LogVol00  
и выясняем, что у нас файловая система XFS, которая не поддерживает уменьшение размера.  
fsadm: Xfs filesystem shrinking is unsupported.  
  /usr/sbin/fsadm failed: 1  
  Filesystem resize failed.

Неприятненько. Значит, чтобы выполнить задание, необходимо будет куда-то скопировать содержимое ФС, удалить старый логический раздел и создать новый нужного размера, отформатировать его в ХФС и вернуть данные на место

На корневой ФС занято 1,7 Гб, и у нас есть диск /dev/sdb  размером 10Гб - его и используем как временный
```
# pvcreate /dev/sdb
  Physical volume "/dev/sdb" successfully created.c
# vgcreate root_tmp /dev/sdb
  Volume group "root_tmp" successfully created
# lvcreate --extents 100%FREE root_tmp
  Logical volume "lvol0" created.
# mkfs.xfs /dev/root_tmp/lvol0
meta-data=/dev/root_tmp/lvol0    isize=512    agcount=4, agsize=130816 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=523264, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
# mount /dev/root_tmp/lvol0 /mnt
# rsync -axu / /mnt
   ```

Чтобы удалить старый раздел, придется загрузиться со временного раздела
Поэтому чрутимся в него, внутри дополнительно примонтируем /boot, который подключен отдельным разделом.
```
for i in dev proc run sys; do mount --bind /${i} /mnt/${i}; done
chroot /mnt
mount /dev/sda2 /boot
```

Во временном разделе редактируем /etc/fstab,где вставляем ссылку на новый LV  
Генерируем новый grub.cfg  
В конфиге (/boot/grub2/grub.conf) в опциях ядра указаны в явном виде, какие разделы LVM подключать при загрузке. Нашего нового раздела там нет, не появился он и после обновления конфига граба. Поэтому добавляем его вручную перед другими разделами по аналогии с опцией lvm.rd.lv=.

Теперь необходимо создать файл /.autorelabel, чтобы SELinux переразметил файлы на новом разделе, с которого мы грузимся.
Чтобы переразметка произошла, необходимо передать в опции загрузки ядра enforcing=0 . Её так же надо добавить в grub.conf нового раздела
```
[root@localhost /]# mount /dev/sda2 /boot
[root@localhost /]# vi /etc/fstab
[root@localhost /]# grub2-mkconfig -o /boot/grub2/grub.cfg
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-3.10.0-862.2.3.el7.x86_64
Found initrd image: /boot/initramfs-3.10.0-862.2.3.el7.x86_64.img
done
[root@localhost /]# vi /boot/grub2/grub.cfg
[root@localhost /]# touch /.autorelabel
```

После перезагрузки убеждаемся, что загрузились со временного раздела и удаляем старый раздел
```
lsblk
lvremove LogVol00
```

Создадим его заново, но уже требуемого размера \
```
lvcreate -L 8G VolGroup00 -n LogVol00
mkfs.xfs /dev/VolGroup00/LogVol00
```
По аналогии с предыдущими действиями монтируем, копируем корневую ФС, чрутимся внутрь созданного раздела, затем генерируем grub.conf, возвращаем /etc/fstab в исходное состояние(т.к. мы вернули старое имя раздела),
добавляем опцию enforcing=0 и создаем файл /.autorelabel. После чего перезагружаемся
```
# rsync -axu / /mnt
# for i in boot dev proc run sys; do mount --bind /${i} /mnt/${i} ; done
# chroot /mnt
# grub2-mkconfig -o /boot/grub2/grub.cfg
# vi /etc/fstab
# touch /.autorelabel
# vi /boot/grub2/grub.cfg
```

После перезагрузки убеждаемся, что корневая ФС на нужном разделе и удаляем временный LV, можно сразу целиком с VG.
```
lsblk
lvremove temp_root/lvol0  
vgremove temp_root  
```
Убираем enforcing=0 из grub.conf - изменение корневого раздела завершено.

>На этом месте я столкнулся с багом, при котором переразметка ФС не происходит
https://github.com/rear/rear-workshop-osbconf-2016/issues/4#issuecomment-286515264
Связано это, судя по всему, с тем, как VirtualBox работает с последовательными портами по умолчанию: если порт не описан - его и нет, а в опциях загрузки ядра у нас последней описываемой консолью идет как раз консоль на последовательном порту - ttyS0.
В качестве воркэраунда удаляем из опций загрузки ядра console=ttyS0,115220.

### Выделить том под /home, под /var
### /var - сделать в mirror
Выделим под /var два одинаковых по объему диска
Делаем VG, затем создадим LV  с нужными опциями
```
# pvcreate /dev/sdd /dev/sde
# vgcreate vg_var /dev/sd{e,d}
# lvcreate -m1 -n lv_var -l 100%FREE vg_var
```
По аналогии с предыдущими действиями создаем ФС, монтируем, копируем туда содержимое каталога, затем добавляем запись в /etc/fstab и перемонтируем уже на требуемое место.
```
# mkfs.xfs /dev/vg_var/lv_var
# mount /dev/vg_var/lv_var /mnt
# rsync -axu /var/ /mnt
# ls /var/
adm  cache  db  empty  games  gopher  kerberos  lib  local  log  nis  opt  preserve  spool  tmp  yp
# umount /dev/vg_var/lv_var
# mount /dev/vg_var/lv_var /var
# ls /var
adm    db     games   kerberos  local  log   nis  preserve  spool  yp
cache  empty  gopher  lib       lock   mail  opt  run       tmp
```
### /home - сделать том для снэпшотов
Сначала создадим и примонтируем раздел под /home
```
# lvcreate -n vg_home -L 2G VolGroup00
# mkfs.xfs /dev/VolGroup00/vg_home
# mount /dev/VolGroup00/vg_home /mnt
# cp -aR /home/* /mnt
# rm -rf /home/*
# umount /dev/VolGroup00/vg_home
# mount /dev/VolGroup00/vg_home /home
# vi /etc/fstab
# lvrename VolGroup00/vg_home lv_home # Исправляем опечатку в названии
  Renamed "vg_home" to "lv_home" in volume group "VolGroup00"
# vi /etc/fstab
```

Создадим в /home немножко файлов
```
for i in {1..20}; do dd if=/dev/urandom of=file${i} bs=1M count=1; done
```
Теперь сделаем снапшот раздела
```
# lvcreate -s -n home_snapshot -L 3G VolGroup00/lv_home
  Reducing COW size 3.00 GiB down to maximum usable size 2.03 GiB.
  Logical volume "home_snapshot" created.
```
>Очевидно, при попытке создать снапшот большего размера, чем исходный раздел, LVM автоматически уменьшил размер снапшота до размера раздела.

Удалим часть файлов и восстановимся из снапшота, предварительно отмонтировав раздел
```
# rm -f file{2,4,6,11,19}
# umount /home
umount: /home: target is busy.
        (In some cases useful info about processes that use
         the device is found by lsof(8) or fuser(1))
[root@lvm vagrant]# umount -l /home
[root@lvm vagrant]# lsof
bash: lsof: command not found
[root@lvm vagrant]# lvconvert --merge /dev/VolGroup00/home_snapshot
  Delaying merge since origin is open.
  Merging of snapshot VolGroup00/home_snapshot will occur on next activation of VolGroup00/lv_home.
```
Из-за того, что какие-то файлы были открыты, а  на стенде не нашлось ни lsof, ни fuser, которые помогли бы завершить процесс, державший их, восстановление снапшота произошло после перезагрузки. Видим, что все удаленные файлы вернулись на место
```
[vagrant@lvm ~]$ ls
file1   file11  file13  file15  file17  file19  file20  file4  file6  file8
file10  file12  file14  file16  file18  file2   file3   file5  file7  file9
```
