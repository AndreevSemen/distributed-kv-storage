# Развенутое kv-хранилище

Распределенное Cartridge kv-хранилище

## Navigation

- `Vagrantfile` - файл настройки виртуальных сред
- `hosts.yml` - объявление инстансов и групп инстансов (переменные и т.д.)
- `playbook.yml` - запуск делигирование на запуск Cartridge-роли

## Usage

### Vagrant

##### Dependencies

- Vagrant
- VirtualBox

Поднимим вирутальные хосты, пробросим порты и подготовим к использованию ***Ansible***.
Для этого введем:

```shell script
vagrant up
```

### Ansible

Установим роль для ***Cartridge***:

```shell script
ansible-galaxy install tarantool.cartridge,1.0.1
```

Проделигируем всем инстансам применить ***Ansible***-конфигурацию

```shell script
ansible-playbook -i hosts.yml playbook.yml
```

