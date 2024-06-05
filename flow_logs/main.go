package main

import (
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/likexian/whois"
	"github.com/xitongsys/parquet-go-source/local"
	"github.com/xitongsys/parquet-go/reader"
)

type FlowLogRecord struct {
	Version     *int32  `parquet:"name=version, type=INT32, repetitiontype=optional"`
	AccountID   *string `parquet:"name=account_id, type=BYTE_ARRAY, convertedtype=UTF8, repetitiontype=optional"`
	InterfaceID *string `parquet:"name=interface_id, type=BYTE_ARRAY, convertedtype=UTF8, repetitiontype=optional"`
	SrcAddr     *string `parquet:"name=srcaddr, type=BYTE_ARRAY, convertedtype=UTF8, repetitiontype=optional"`
	DstAddr     *string `parquet:"name=dstaddr, type=BYTE_ARRAY, convertedtype=UTF8, repetitiontype=optional"`
	SrcPort     *int32  `parquet:"name=srcport, type=INT32, repetitiontype=optional"`
	DstPort     *int32  `parquet:"name=dstport, type=INT32, repetitiontype=optional"`
	Protocol    *int32  `parquet:"name=protocol, type=INT32, repetitiontype=optional"`
	Packets     *int64  `parquet:"name=packets, type=INT64, repetitiontype=optional"`
	Bytes       *int64  `parquet:"name=bytes, type=INT64, repetitiontype=optional"`
	Start       *int64  `parquet:"name=start, type=INT64, repetitiontype=optional"`
	End         *int64  `parquet:"name=end, type=INT64, repetitiontype=optional"`
	Action      *string `parquet:"name=action, type=BYTE_ARRAY, convertedtype=UTF8, repetitiontype=optional"`
	LogStatus   *string `parquet:"name=log_status, type=BYTE_ARRAY, convertedtype=UTF8, repetitiontype=optional"`
}

// AggregateTalkers aggregates bytes by the specified address type (SrcAddr or DstAddr).
func AggregateTalkers(dirPath string, addressType string) (map[string]int64, error) {
	talkers := make(map[string]int64)
	const batchSize = 1000

	err := filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || filepath.Ext(path) != ".parquet" {
			return nil
		}

		fr, err := local.NewLocalFileReader(path)
		if err != nil {
			log.Printf("Error opening file: %v\n", err)
			return err
		}
		defer fr.Close()

		pr, err := reader.NewParquetReader(fr, new(FlowLogRecord), 4)
		if err != nil {
			log.Printf("Error creating Parquet reader: %v\n", err)
			return err
		}
		defer pr.ReadStop()

		num := int(pr.GetNumRows())

		for i := 0; i < num; {
			records := make([]FlowLogRecord, batchSize)
			if err = pr.Read(&records); err != nil {
				log.Printf("Error reading Parquet file: %v\n", err)
				break
			}

			for _, record := range records {
				var addr *string
				if addressType == "SrcAddr" {
					addr = record.SrcAddr
				} else if addressType == "DstAddr" {
					addr = record.DstAddr
				} else {
					return fmt.Errorf("invalid address type: %s", addressType)
				}

				if addr != nil && record.Bytes != nil {
					// Skip private IP addresses
					isPrivate, err := isPrivateIP(*addr)
					if err != nil {
						log.Printf("Error checking if IP address is private: %v\n", err)
						continue
					}
					if isPrivate {
						continue
					}
					talkers[*addr] += *record.Bytes
				}
			}

			i += len(records)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	return talkers, nil
}

// talker represents a combination of source IP with the total bytes.
type talker struct {
	IP    string
	Bytes int64
}

// printTopTalkers prints the top talkers sorted by bytes.
func printTopTalkers(talkers map[string]int64, topN int) {
	var talkerSlice []talker
	for ip, bytes := range talkers {
		talkerSlice = append(talkerSlice, talker{IP: ip, Bytes: bytes})
	}

	sort.Slice(talkerSlice, func(i, j int) bool {
		return talkerSlice[i].Bytes > talkerSlice[j].Bytes
	})

	// Print the top sources
	for i, t := range talkerSlice {
		if i >= topN {
			break
		}
		// do a WHOIS lookup to get the organization name
		orgName, err := getOrgNameFromWhois(t.IP)
		if err != nil {
			fmt.Printf("IP: %s, Bytes: %d\n", t.IP, t.Bytes)
		} else {
			fmt.Printf("IP: %s, Bytes: %d, Organization: %s\n", t.IP, t.Bytes, orgName)
		}
	}
}

// getOrgNameFromWhois performs a WHOIS lookup and returns the organization name
func getOrgNameFromWhois(ip string) (string, error) {
	result, err := whois.Whois(ip)
	if err != nil {
		return "", err
	}

	return parseOrgName(result), nil
}

// parseOrgName tries to parse the organization name from the WHOIS response
func parseOrgName(whoisResponse string) string {
	lines := strings.Split(whoisResponse, "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "OrgName:") || strings.HasPrefix(line, "organisation:") {
			return strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		}
	}
	return "Organization name not found"
}

// describeEniResource takes an ENI ID and returns the associated resource information
func describeEniResource(region string, eniID string) (string, error) {
	sess, err := session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	})
	if err != nil {
		fmt.Println("Failed to create session:", err)
		os.Exit(1)
	}
	svc := ec2.New(sess)

	// Describe the specific ENI
	input := &ec2.DescribeNetworkInterfacesInput{
		NetworkInterfaceIds: []*string{aws.String(eniID)},
	}
	result, err := svc.DescribeNetworkInterfaces(input)
	if err != nil {
		return "", fmt.Errorf("%w", err)
	}

	if len(result.NetworkInterfaces) == 0 {
		return "", fmt.Errorf("no network interface found with ID %s", eniID)
	}

	eni := result.NetworkInterfaces[0]
	if eni.Attachment == nil {
		return "ENI is not attached", nil
	}

	// Determine the type of resource the ENI is attached to
	resourceType := aws.StringValue(eni.Attachment.InstanceOwnerId)
	switch resourceType {
	case "amazon-aws":
		return "ENI attached to an AWS managed resource", nil
	default:
		return fmt.Sprintf("ENI attached to a resource of type: %s", resourceType), nil
	}
}

// isPrivateIP checks if a given IP address string is a private IP address.
func isPrivateIP(ipStr string) (bool, error) {
	ip := net.ParseIP(ipStr)
	if ip == nil {
		return false, fmt.Errorf("invalid IP address: %s", ipStr)
	}

	_, private10, _ := net.ParseCIDR("10.0.0.0/8")
	_, private172, _ := net.ParseCIDR("172.16.0.0/12")
	_, private192, _ := net.ParseCIDR("192.168.0.0/16")

	return private10.Contains(ip) || private172.Contains(ip) || private192.Contains(ip), nil
}

// countEniOccurrences counts the occurrences of each ENI in the specified directory
func countEniOccurrences(dirPath string) (map[string]int, error) {
	eniCounts := make(map[string]int)
	const batchSize = 1000

	err := filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || filepath.Ext(path) != ".parquet" {
			return nil
		}

		fr, err := local.NewLocalFileReader(path)
		if err != nil {
			return err
		}
		defer fr.Close()

		pr, err := reader.NewParquetReader(fr, new(FlowLogRecord), 4)
		if err != nil {
			return err
		}
		defer pr.ReadStop()

		num := int(pr.GetNumRows())

		for i := 0; i < num; {
			records := make([]FlowLogRecord, batchSize)
			if err = pr.Read(&records); err != nil {
				return err
			}

			for _, record := range records {
				if record.InterfaceID != nil {
					eniCounts[*record.InterfaceID]++
				}
			}

			i += len(records)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	return eniCounts, nil
}

// getNatGatewayEnis returns a map of NAT Gateway IDs to their associated ENI IDs
func getNatGatewayEnis(region string) (map[string]string, error) {
	sess, err := session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	})
	if err != nil {
		fmt.Println("Failed to create session:", err)
		os.Exit(1)
	}

	svc := ec2.New(sess)

	// Describe NAT Gateways
	natGateways, err := svc.DescribeNatGateways(&ec2.DescribeNatGatewaysInput{})
	if err != nil {
		return nil, fmt.Errorf("failed to describe NAT Gateways: %w", err)
	}

	enis := make(map[string]string)
	for _, ngw := range natGateways.NatGateways {
		for _, ngwAddr := range ngw.NatGatewayAddresses {
			if ngw.NatGatewayId != nil && ngwAddr.NetworkInterfaceId != nil {
				enis[*ngw.NatGatewayId] = *ngwAddr.NetworkInterfaceId
			}
		}
	}

	return enis, nil
}

func main() {
	const dirPath = "../s3/fetch/working/03/21/"
	talkers, err := AggregateTalkers(dirPath, "SrcAddr")
	if err != nil {
		log.Fatalf("Error aggregating talkers: %v", err)
	}
	log.Printf("Top talkers aggregated by source address:\n")
	printTopTalkers(talkers, 10)
	talkers, err = AggregateTalkers(dirPath, "DstAddr")
	if err != nil {
		log.Fatalf("Error aggregating talkers: %v", err)
	}
	log.Printf("Top talkers aggregated by destination address:\n")
	printTopTalkers(talkers, 10)
}
