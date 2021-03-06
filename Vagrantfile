# -*- mode: ruby -*-
# vi: set ft=ruby :

# list of VM boxes, that could be upped
# :name  - of VM
# :ip    - VMs' address
# :ports - list of exposed ports
vm_boxes = [
    {
        :name  => "v-machine1",
        :ip    => "172.19.0.2",
        :ports => [8800, 8801]
    },
    {
        :name  => "v-machine2",
        :ip    => "172.19.0.3",
        :ports => [8802, 8803]
    }
]


Vagrant.configure("2") do |config|
    # we use centos distribution
    config.vm.box = "ubuntu/trusty64"

    # setting up synced folder for quick sharing
    # deb-package between host and guest
    config.vm.synced_folder "./shared/", "/shared"

    # disable auto insertion of SSH-keys
    config.ssh.insert_key = false

    config.vm.provider "virtualbox" do |vb|
        vb.memory = "2048"
    end

    config.vm.provision "shell", inline: <<-SHELL
        apt-get install -y systemd
    SHELL

    vm_boxes.each_with_index do |box, index|
        config.vm.define box[:name] do |box_config|
            box_config.vm.hostname = box[:name]
            # creating private guest network points
            box_config.vm.network "private_network", ip: box[:ip]
            # exposing of every included port of current VM
            box[:ports].each do |port|
                # mapping of host-guest ports
                box_config.vm.network "forwarded_port",
                                      guest:       port,
                                      host:        port,
                                      autocorrect: true
            end
        end
    end

end