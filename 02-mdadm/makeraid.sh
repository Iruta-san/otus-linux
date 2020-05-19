# Сперва занулим суперблоки. Непонятно зачем, диски "новые", но хуже точно не будет
# Здесь было бы неплохо добавить проверку, что мы не тронем диск с системным разделом, 
# т.к. не всегда виртуалка грузит диски в одном и том же порядке...
# Посмотреть список дисков без разметки можно так:
# lsblk -o NAME,FSTYPE -dsn | awk '$2 == "" {print $1}'
# Источник: https://unix.stackexchange.com/questions/412483/how-to-capture-all-disks-that-don-t-have-a-file-system
# Записать в переменную одной строкой: 
# disks=$(lsblk -o NAME,FSTYPE -dsn | awk '$2 == "" {print $1}' | sed 's/^/\/dev\//g' | sed -z 's/\n/ /g')
# Еще надо понять, как из вывода убрать один(последний?) диск, чтобы оставить его под запас.
# Как вариант, брать все возможные диски и подставлять их количество через wc

mdadm --zero-superblock --force /dev/sd{b,c,d,e,f}

# Создаем RAID5
mdadm --create --verbose /dev/md0 -l 5 -n 5 /dev/sd{b,c,d,e,f}

# Записываем в конфигурацию
echo "DEVICE partitions" > /etc/mdadm.conf
mdadm --detail --scan --verbose | awk '/ARRAY/ {print}' >> /etc/mdadm.conf

# Создаем GPT-разметку
parted -s /dev/md0 mklabel gpt

# Размечаем райд на 5 равных разделов
parted /dev/md0 mkpart primary ext4 0% 20%
parted /dev/md0 mkpart primary ext4 20% 40%
parted /dev/md0 mkpart primary ext4 40% 60%
parted /dev/md0 mkpart primary ext4 60% 80%
parted /dev/md0 mkpart primary ext4 80% 100%

# Создаем ФС и сразу ее монтируем
for i in $(seq 1 5); do 
	mkfs.ext4 /dev/md0p$i
	mkdir -p /raid/part$i
	mount /dev/md0p$i /raid/part$i
done

# Генерируем конфиг fstab для автомонтирования
lsblk -f | grep md0p | awk '{print $3" "$4" ext4 defaults 0 0"}' | sort | uniq >> /etc/fstab