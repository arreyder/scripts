package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/alecthomas/chroma/formatters"
	"github.com/alecthomas/chroma/lexers"
	"github.com/alecthomas/chroma/styles"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/rds"
)

func main() {
	sess, err := session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	})
	if err != nil {
		fmt.Println("Failed to create session:", err)
		os.Exit(1)
	}

	svc := rds.New(sess)

	result, err := svc.DescribeDBInstances(nil)
	if err != nil {
		fmt.Println("Error", err)
		os.Exit(1)
	}

	fmt.Println("Select an RDS instance:")
	for i, db := range result.DBInstances {
		fmt.Printf("%d. %s\n", i+1, *db.DBInstanceIdentifier)
	}

	var choice int
	fmt.Print("Enter the number of the RDS instance: ")
	_, err = fmt.Scan(&choice)
	if err != nil {
		fmt.Println("Invalid input:", err)
		os.Exit(1)
	}
	if choice < 1 || choice > len(result.DBInstances) {
		fmt.Println("Invalid choice")
		os.Exit(1)
	}

	selectedInstance := result.DBInstances[choice-1]
	fmt.Println("Selected Instance:", *selectedInstance.DBInstanceIdentifier)

	fmt.Println("Tailing logs...")
	err = tailLogs(svc, *selectedInstance.DBInstanceIdentifier)
	if err != nil {
		fmt.Println("Error tailing logs:", err)
	}
}

func tailLogs(svc *rds.RDS, instanceIdentifier string) error {
	var lastMarker string

	for {
		output, err := svc.DescribeDBLogFiles(&rds.DescribeDBLogFilesInput{
			DBInstanceIdentifier: aws.String(instanceIdentifier),
		})
		if err != nil {
			return err
		}

		if len(output.DescribeDBLogFiles) == 0 {
			fmt.Println("No logs found.")
			continue
		}

		sort.SliceStable(output.DescribeDBLogFiles, func(i, j int) bool {
			return *output.DescribeDBLogFiles[i].LastWritten > *output.DescribeDBLogFiles[j].LastWritten
		})

		mostRecentLogFile := output.DescribeDBLogFiles[0]
		newMarker, err := downloadAndPrintLog(svc, instanceIdentifier, *mostRecentLogFile.LogFileName, lastMarker)
		if err != nil {
			return err
		}

		lastMarker = newMarker
		time.Sleep(10 * time.Second)
	}
}

func downloadAndPrintLog(svc *rds.RDS, instanceIdentifier, logFileName, lastMarker string) (string, error) {
	input := &rds.DownloadDBLogFilePortionInput{
		DBInstanceIdentifier: aws.String(instanceIdentifier),
		LogFileName:          aws.String(logFileName),
		Marker:               aws.String(lastMarker),
	}

	output, err := svc.DownloadDBLogFilePortion(input)
	if err != nil {
		return "", err
	}

	scanner := bufio.NewScanner(strings.NewReader(*output.LogFileData))
	for scanner.Scan() {
		line := scanner.Text()
		colorizedLine := colorizeLogLine(line)
		fmt.Println(colorizedLine)
	}

	if output.Marker == nil {
		return lastMarker, nil
	}

	return *output.Marker, scanner.Err()
}

func colorizeLogLine(line string) string {
	lexer := lexers.Get("postgresql")
	formatter := formatters.Get("terminal256")
	iterator, err := lexer.Tokenise(nil, line)
	if err != nil {
		return line // Fallback to the original line on error
	}

	var b bytes.Buffer
	err = formatter.Format(&b, styles.Get("monokai"), iterator)
	if err != nil {
		return line // Fallback on error
	}
	return b.String()
}
