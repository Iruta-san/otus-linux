Определить алгоритм с наилучшим сжатием

 Определить настройки pool’a
https://drive.google.com/open?id=1KRBNW33QWqbvbVHa3hLJivOAt60yukkg 

Найти сообщение от преподавателей 

### Подготовка стенда
Был задействован Vagrantfile из домашки по mdadm. В нем изменяем количество дисков до восьми и устанавливаем zfs с помощью скрипта.

В корне репозитория лежат файлы Vagrantfile и getzfs.sh, необходимые для воссоздания рабочего стенда.

### Определить алгоритм с наилучшим сжатием
```
# modprobe zfs
# zpool create mypool /dev/sd[b-i]
# zpool status
# for i in gzip lz4 lzjb zle; do zfs create mypool/fs_${i} -o compression=${i} ; done
# zfs list
NAME             USED  AVAIL     REFER  MOUNTPOINT
mypool           277K  7.27G       28K  /mypool
mypool/fs_gzip    24K  7.27G       24K  /mypool/fs_gzip
mypool/fs_lz4     24K  7.27G       24K  /mypool/fs_lz4
mypool/fs_lzjb    24K  7.27G       24K  /mypool/fs_lzjb
mypool/fs_zle     24K  7.27G       24K  /mypool/fs_zle
```

Пробуем по очереди распаковать исходные коды ядра линукс, заодно сравним время записи
```
# curl -O https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.7.tar.xz
# tar xvf linux-5.7.tar.xz
# for i in lz4 lzjb zle ; do time cp -af linux-5.7/ /mypool/fs_${i}/ ; zfs get compression,compressratio mypool/fs_${i} ; done
real    5m14.517s
user    0m2.246s
sys     2m45.677s
NAME            PROPERTY       VALUE     SOURCE
mypool/fs_gzip  compression    gzip      local
mypool/fs_gzip  compressratio  4.25x     -
real    2m56.609s
user    0m0.124s
sys     2m1.850s
NAME           PROPERTY       VALUE     SOURCE
mypool/fs_lz4  compression    lz4       local
mypool/fs_lz4  compressratio  2.77x     -

real    2m38.897s
user    0m0.104s
sys     1m53.042s
NAME            PROPERTY       VALUE     SOURCE
mypool/fs_lzjb  compression    lzjb      local
mypool/fs_lzjb  compressratio  2.40x     -

real    2m29.615s
user    0m0.076s
sys     1m51.113s
NAME           PROPERTY       VALUE     SOURCE
mypool/fs_zle  compression    zle       local
mypool/fs_zle  compressratio  1.08x     -

```
В итоге видно, что gzip обладает лучшей степенью сжатия (из документации узнаём, что по умолчанию степень сжатия 6 при максимально возможной 9), но наиболее медленной записью на диск. Алгоритм lz4 выглядит золотой серединкой: в полтора раза меньше степень сжатия, чем у gzip, но в 1,8 раза быстрее работает.

### Определить настройки pool'a
Скачиваем
```
 wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1KRBNW33QWqbvbVHa3hLJivOAt60yukkg' -O zfs_task1.tar.gz
 ```

Импортируем
```
# zpool import -d zpoolexport/
   pool: otus
     id: 6554193320433390805
  state: ONLINE
 action: The pool can be imported using its name or numeric identifier.
 config:

        otus                                 ONLINE
          mirror-0                           ONLINE
            /home/vagrant/zpoolexport/filea  ONLINE
            /home/vagrant/zpoolexport/fileb  ONLINE
# zpool import -d zpoolexport/ otus
# zpool status -v otus
  pool: otus
 state: ONLINE
  scan: none requested
config:

        NAME                                 STATE     READ WRITE CKSUM
        otus                                 ONLINE       0     0     0
          mirror-0                           ONLINE       0     0     0
            /home/vagrant/zpoolexport/filea  ONLINE       0     0     0
            /home/vagrant/zpoolexport/fileb  ONLINE       0     0     0

errors: No known data errors

# zfs list
NAME             USED  AVAIL     REFER  MOUNTPOINT
mypool          1.93G  5.34G       28K  /mypool
mypool/fs_gzip   249M  5.34G      249M  /mypool/fs_gzip
mypool/fs_lz4    373M  5.34G      373M  /mypool/fs_lz4
mypool/fs_lzjb   428M  5.34G      428M  /mypool/fs_lzjb
mypool/fs_zle    924M  5.34G      924M  /mypool/fs_zle
otus            2.04M   350M       24K  /otus
otus/hometask2  1.88M   350M     1.88M  /otus/hometask2
```

Узнаем требуемые настройки
```
# zfs get quota,reservation,available,recordsize,compression,checksum otus
NAME  PROPERTY     VALUE      SOURCE
otus  quota        none       default
otus  reservation  none       default
otus  available    350M       -
otus  recordsize   128K       local
otus  compression  zle        local
otus  checksum     sha256     local
```
Итого, имеем следующие ответы:
 - размер хранилища 350 МБ без квот и резервирования пространства
 - тип pool - mirror
 - Значение recordsize 128K
 - сжатие zle
 - контрольная сумма sha256

### Найти сообщение от преподавателей
Качаем файл с заданием
```
# wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1KRBNW33QWqbvbVHa3hLJivOAt60yukkg' -O otus_task2.file
```

Импортируем снапшот, смотрим типы файлов для поиска
```
[root@zfshw vagrant]# zfs receive mypool/task2 < otus_task2.file
[root@zfshw vagrant]# zfs list
NAME             USED  AVAIL     REFER  MOUNTPOINT
mypool          1.93G  5.33G       28K  /mypool
mypool/fs_gzip   249M  5.33G      249M  /mypool/fs_gzip
mypool/fs_lz4    373M  5.33G      373M  /mypool/fs_lz4
mypool/fs_lzjb   428M  5.33G      428M  /mypool/fs_lzjb
mypool/fs_zle    924M  5.33G      924M  /mypool/fs_zle
mypool/task2    3.69M  5.33G     3.69M  /mypool/task2
otus            1.98M   350M       24K  /otus
otus/hometask2  1.81M   350M     1.81M  /otus/hometask2
[root@zfshw vagrant]# cd /mypool/task2/
[root@zfshw task2]# ls
10M.file  cinderella.tar  for_examaple.txt  homework4.txt  Limbo.txt  Moby_Dick.txt  task1  War_and_Peace.txt  world.sql
[root@zfshw task2]# file *
10M.file:          empty
cinderella.tar:    POSIX tar archive (GNU)
for_examaple.txt:  ASCII text
homework4.txt:     empty
Limbo.txt:         C++ source, UTF-8 Unicode (with BOM) text, with CRLF line terminators
Moby_Dick.txt:     gzip compressed data, was "pg2701.txt.utf8.gzip", last modified: Sun Oct  2 06:24:43 2016, max compression
task1:             directory
War_and_Peace.txt: gzip compressed data, was "pg2600.txt.utf8.gzip", last modified: Fri May  6 22:42:10 2016, max compression
world.sql:         UTF-8 Unicode text
```
Вроде пока ничего интересного. Походим по директориям, что там?
```
[root@zfshw task2]# cd task1/
[root@zfshw task1]# ls
file_mess  README
```
Почитаем README, потом посмотрим внутрь ./file_mess
```
[root@zfshw task1]# less README
[root@zfshw task1]# cd file_mess/
[root@zfshw file_mess]# ls
[...очень много файлов..]
secret_message
[...еще немножко файлов...]
```
Видимо, предполагалось выполнить задание из README, чтобы в директории остался только файл secret_message, но так получилось, что он бросился в глаза с первого же раза.

Наконец, смотрим сообщение от преподавателей:
```
[root@zfshw file_mess]# cat secret_message
https://github.com/sindresorhus/awesome
```

# AWESOME!