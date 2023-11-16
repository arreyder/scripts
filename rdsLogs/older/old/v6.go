package main

import (
	"bufio"
	"fmt"
	"io/ioutil"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/rds"
)

const positionFile = "position.txt"

var logStartPattern = regexp.MustCompile(`^[\d-]{10} [\d:]{8} UTC:[^:]*:[^@]*@[^:]*:\[\d*\]:.*$|^[\d-]{10} [\d:]{8} UTC::@:\[\d*\]:LOG:.*$`)

func main() {

	sess, err := session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	})

	if err != nil {
		fmt.Printf("Failed to create AWS session: %v\n", err)
		os.Exit(1)
	}

	svc := rds.New(sess)

	dbInstance := os.Getenv("DB_INSTANCE")

	var marker string
	if pos, err := ioutil.ReadFile(positionFile); err == nil {
		marker = string(pos)
	} else if !os.IsNotExist(err) {
		fmt.Printf("Failed to read position file: %v\n", err)
		os.Exit(1)
	}

	for {
		input := &rds.DescribeDBLogFilesInput{
			DBInstanceIdentifier: aws.String(dbInstance),
		}

		result, err := svc.DescribeDBLogFiles(input)
		if err != nil {
			fmt.Printf("Failed to describe DB log files: %v\n", err)
			time.Sleep(1 * time.Minute)
			continue
		}

		sort.Slice(result.DescribeDBLogFiles, func(i, j int) bool {
			return aws.Int64Value(result.DescribeDBLogFiles[i].LastWritten) > aws.Int64Value(result.DescribeDBLogFiles[j].LastWritten)
		})

		for _, file := range result.DescribeDBLogFiles {
			if marker != "" && *file.LogFileName != marker {
				continue
			}

			logInput := &rds.DownloadDBLogFilePortionInput{
				DBInstanceIdentifier: aws.String(dbInstance),
				LogFileName:          file.LogFileName,
			}

			logResult, err := svc.DownloadDBLogFilePortion(logInput)
			if err != nil {
				fmt.Printf("Failed to download DB log file portion: %v\n", err)
				break
			}

			scanner := bufio.NewScanner(strings.NewReader(*logResult.LogFileData))

			var logLine string
			for scanner.Scan() {
				line := scanner.Text()
				if logStartPattern.MatchString(line) {
					if logLine != "" {
						fmt.Println(logLine)
					}
					logLine = line
				} else {
					logLine += line
				}
			}

			if scanner.Err() != nil {
				fmt.Printf("Failed to scan DB log file data: %v\n", scanner.Err())
				break
			} else if logLine != "" {
				fmt.Println(logLine)
			}

			marker = *file.LogFileName
			if err := ioutil.WriteFile(positionFile, []byte(marker), 0644); err != nil {
				fmt.Printf("Failed to write position file: %v\n", err)
				os.Exit(1)
			}
		}

		time.Sleep(1 * time.Minute)
	}
}
