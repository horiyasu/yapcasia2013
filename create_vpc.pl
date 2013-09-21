#!/usr/bin/env perl
use strict;

use AWS::CLIWrapper;
use Data::Dumper;

my $aws = AWS::CLIWrapper->new(
    region => 'ap-northeast-1',
);

# create VPC 10.0.0.0/16
# aws ec2 create-vpc --cidr-block 10.0.0.0/16
my $res_vpc = $aws->ec2(
    'create-vpc' => {
        'cidr-block' => '10.0.0.0/16',
    },
);

my $vpc_id = $res_vpc->{'Vpc'}{'VpcId'};
my $state = $res_vpc->{'Vpc'}{'State'};

print "created vpc. vpc-id is $vpc_id\n";

# wait for finishing VPC creation
while ($state ne 'available') {
    # aws ec2 describe-vpcs --vpc-ids $vpc_id
    my $res = $aws->ec2(
        'describe-vpcs' => {
            'vpc-ids'=>[$vpc_id],
        },
    );
    $state = $res->{'Vpcs'}->[0]->{'State'};
}

# create subnet 10.0.0.0/24
# aws ec2 create-subnet --vpc-id $vpc_id  --cidr-block 10.0.0.0/24 --availability-zone ap-northeast-1a
my $res_subnet = $aws->ec2(
    'create-subnet' => {
        'vpc-id' => $vpc_id,
        'cidr-block' => '10.0.0.0/24',
        'availability-zone' => 'ap-northeast-1a',
    },
);

my $subnet_id = $res_subnet->{'Subnet'}{'SubnetId'};
print "created subnet. subnet-id is $subnet_id\n";

# create route table
# aws ec2 create-route-table --vpc-id $vpc_id
my $res_route_table = $aws->ec2(
    'create-route-table' => {
        'vpc-id' => $vpc_id,
    },
);
my $route_table_id = $res_route_table->{'RouteTable'}{'RouteTableId'};
print "created route table. route-table-id is $route_table_id\n";

# crete internet gateway
# aws ec2 create-internet-gateway
my $res_igw = $aws->ec2(
    'create-internet-gateway'
);

my $igw_id = $res_igw->{'InternetGateway'}{'InternetGatewayId'};
print "created internet gateway. internet-gateway-id is $igw_id\n";

# attache internet gateway to vpc
# aws ec2 attach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id
$res_igw = $aws->ec2(
    'attach-internet-gateway' => {
        'internet-gateway-id' => $igw_id,
        'vpc-id' => $vpc_id,
    },
);

if (! $res_igw || $res_igw->{'return'} ne 'true' ) {
    exit_error();
}
print "attached internet gateway to vpc.\n";

# create route for internet gateway in route table
# aws ec2 create-route --route-table-id $route_table_id --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id
my $res_route = $aws->ec2(
    'create-route' => {
        'route-table-id' => $route_table_id,
        'destination-cidr-block' => '0.0.0.0/0',
        'gateway-id' => $igw_id,
    },
);
if (! $res_route || $res_route->{'return'} ne 'true' ) {
    exit_error();
}
print "created route for internet gateway in route table\n";

# assosiate route table with subnet
# aws ec2 associate-route-table --subnet-id $subnet_id --route-table-id $route_table_id
$res_route = $aws->ec2(
    'associate-route-table' => {
        'subnet-id' => $subnet_id,
        'route-table-id' => $route_table_id,
    }
);

my $associate_id = $res_route->{'AssociationId'};
print "associated route table with subnet. associate-id is $associate_id\n";

# create security group 
# aws ec2 create-security-group --group-name mt-app --description mt-app --vpc-id $vpc_id
my $res_sg = $aws->ec2(
    'create-security-group' => {
        'group-name' => 'mt-app',
        'description' => 'mt-app',
        'vpc-id' => $vpc_id,
    },
);
if (! $res_sg || $res_sg->{'return'} ne 'true' ) {
    exit_error();
}

my $sg_id = $res_sg->{'GroupId'};
print "created security group. group-id is $sg_id\n";

#aws ec2 authorize-security-group-ingress --group-id sg-51d0303e  --protocol tcp --port 22 --cidr 0.0.0.0/0
$res_sg = $aws->ec2(
    'authorize-security-group-ingress' => {
        'group-id' => $sg_id,
        'protocol' => 'tcp',
        'port' => '22',
        'cidr' => '0.0.0.0/0',
    },
);
print "authorized TCP:22 to security group\n";

#aws ec2 authorize-security-group-ingress --group-id sg-51d0303e  --protocol tcp --port 80 --cidr 0.0.0.0/0
$res_sg = $aws->ec2(
    'authorize-security-group-ingress' => {
        'group-id' => $sg_id,
        'protocol' => 'tcp',
        'port' => '80',
        'cidr' => '0.0.0.0/0',
    },
);
print "authorized TCP:80 to security group\n";

# run instance in subnet in vpc.
# aws ec2 run-instances --image-id ami-67f36c66 --count 1 --instance-type t1.micro --key-name horiuchi --security-group-ids sg-51d0303e --subnet-id subnet-093e7a61

my $res_instance = $aws->ec2(
    'run-instances' => {
        'image-id' => 'ami-67f36c66',
        'count' => '1',
        'instance-type' => 't1.micro',
        'key-name' => 'horiuchi',
        'security-group-ids' => $sg_id,
        'subnet-id' => $subnet_id,
    },
);

my $instance_id = $res_instance->{'Instances'}->[0]->{'InstanceId'};
my $instance_status = $res_instance->{'Instances'}->[0]->{'State'}->{'Name'};

print "starting ec2 instance. instance-id is $instance_id\n";

# wait for running instance
print "waiting for running instance";
while ($instance_status ne 'running') {
    # aws ec2 describe-instances --instance-ids i-809b2e85 
    my $res = $aws->ec2(
        'describe-instances' => {
            'instance-ids' => $instance_id,
        },
    );
    $instance_status = $res->{'Reservations'}->[0]->{'Instances'}->[0]->{'State'}->{'Name'};
    sleep (1);
    print ".";
}
print "status changed instance is now running.\n";

# add tag
# aws ec2 create-tags --resources $instance_id --tags Key=Name,Value=YAPC
my $res_tag = $aws->ec2(
    'create-tags',{
        'resources' => $instance_id,
        'tags' => 'Key=Name,Value=YAPC',
    },
);

# get allocation-id of eip 54.238.140.141
# aws ec2 describe-addresses --filter Name=public-ip,Values=54.238.140.141
my $res_eip = $aws->ec2(
    'describe-addresses' => {
        'filter' => 'Name=public-ip,Values=54.238.140.141',
    },
);
my $allocation_id = $res_eip->{'Addresses'}->[0]->{'AllocationId'};
print "got allocation-id of eip 54.238.140.141. id is $allocation_id\n";

if ( $res_eip->{'Addresses'}->[0]->{'InstanceId'}) {
    # detach eip if eip is already attached to other instance.
    # aws ec2 disassociate-address --association-id xxxxxxx
    my $res = $aws->ec2(
        'disassociate-address' => {
            'association-id' => $res_eip->{'Addresses'}->[0]->{'AssociationId'}
        },
    );
}

# associate eip with instance
# aws ec2 associate-address --instance-id i-cfd799ca --allocation-id eipalloc-4a4a0e22 
$res_eip = $aws->ec2(
    'associate-address' => {
        'instance-id' => $instance_id,
        'allocation-id' => $allocation_id,
    },
);
if (! $res_eip || $res_eip->{'return'} ne 'true' ) {
    exit_error();
}
print "associated eip with instance.\n";

print "Successfully finished all processes.\n";

sub exit_error {
    die "Error occured in the process\n";
}
