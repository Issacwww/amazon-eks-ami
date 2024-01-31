package util

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/awslabs/amazon-eks-ami/nodeadm/internal/api"
	"go.uber.org/zap"
	"time"
)

const (
	privateDNSNameMaxAttempts     = 20
	privateDNSNameAttemptInterval = 6 * time.Second
)

func GetPrivateDNSNameWithRetry(cfg *api.NodeConfig) (string, error) {
	zap.L().Info(fmt.Sprintf("get PrivateDnsName for instance %v via ec2 client", cfg.Status.Instance.ID))
	awsConfig, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(cfg.Status.Instance.Region))
	if err != nil {
		return "", err
	}
	ec2Client := ec2.NewFromConfig(awsConfig)

	var privateDNSName string
	for attempt := 0; attempt < privateDNSNameMaxAttempts; attempt++ {
		privateDNSName, err := getPrivateDNSName(context.Background(), ec2Client, cfg.Status.Instance.ID)
		if err != nil {
			return "", err
		} else if privateDNSName != "" {
			break
		}

		zap.L().Warn(fmt.Sprintf("PrivateDnsName is not available, attempt %d, waiting for %v...", attempt, privateDNSNameAttemptInterval))
		time.Sleep(privateDNSNameAttemptInterval)
	}
	zap.L().Info(fmt.Sprintf("PrivateDnsName=[%v] for instance %v", privateDNSName, cfg.Status.Instance.ID))
	return privateDNSName, nil
}

func getPrivateDNSName(ctx context.Context, ec2Client *ec2.Client, instanceId string) (string, error) {
	result, err := ec2Client.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
		InstanceIds: []string{instanceId},
	})
	if err != nil {
		return "", err
	}

	for _, reservation := range result.Reservations {
		for _, instance := range reservation.Instances {
			if instance.PrivateDnsName != nil {
				return *instance.PrivateDnsName, nil
			}
		}
	}

	return "", fmt.Errorf("no instance data found")
}
