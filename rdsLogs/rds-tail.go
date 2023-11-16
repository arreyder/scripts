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
	"github.com/logrusorgru/aurora"
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
	input := &rds.DescribeDBLogFilesInput{
		DBInstanceIdentifier: aws.String(instanceIdentifier),
	}

	for {
		output, err := svc.DescribeDBLogFiles(input)
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
		err = downloadAndPrintLog(svc, instanceIdentifier, *mostRecentLogFile.LogFileName)
		if err != nil {
			return err
		}

		time.Sleep(10 * time.Second) // Wait before polling again
	}
}

func downloadAndPrintLog(svc *rds.RDS, instanceIdentifier, logFileName string) error {
	fmt.Printf("Viewing log file: %s\n", logFileName)

	input := &rds.DownloadDBLogFilePortionInput{
		DBInstanceIdentifier: aws.String(instanceIdentifier),
		LogFileName:          aws.String(logFileName),
		NumberOfLines:        aws.Int64(100), // Adjust as needed
	}

	output, err := svc.DownloadDBLogFilePortion(input)
	if err != nil {
		return err
	}

	au := aurora.NewAurora(true)
	scanner := bufio.NewScanner(strings.NewReader(*output.LogFileData))
	for scanner.Scan() {
		line := scanner.Text()
		colorizedLine := colorizeLogLine(line, au)
		fmt.Println(colorizedLine)
	}

	return scanner.Err()
}

func colorizeLogLine(line string, au aurora.Aurora) string {
	/*	parts := strings.SplitN(line, " ", 5)
		if len(parts) < 5 {
			return au.White(line).String() // Non-standard lines in default color
		}

		// Extracting timestamp and log level
		timestamp := parts[0] + " " + parts[1]
		logLevel := parts[4]

		var levelColorized aurora.Value
		switch {
		case strings.Contains(logLevel, "ERROR"):
			levelColorized = au.Red(logLevel)
		case strings.Contains(logLevel, "WARNING"):
			levelColorized = au.Yellow(logLevel)
		case strings.Contains(logLevel, "LOG"):
			levelColorized = au.Cyan(logLevel)
		default:
			levelColorized = au.White(logLevel)
		}
	*/

	// Detecting SQL content
	if strings.Contains(line, "SELECT") || strings.Contains(line, "INSERT") || strings.Contains(line, "ALTER") ||
		strings.Contains(line, "WITH") || strings.Contains(line, "CREATE") || strings.Contains(line, "EXPLAIN") ||
		strings.Contains(line, "UPDATE") || strings.Contains(line, "DELETE") || strings.Contains(line, "VALUES") ||
		strings.Contains(line, "FROM") || strings.Contains(line, "WHERE") || strings.Contains(line, "WITH") {
		lexer := lexers.Get("PostgreSQL")
		formatter := formatters.Get("terminal256")
		iterator, err := lexer.Tokenise(nil, line)
		if err != nil {
			return au.BrightBlue(line).String() // Fallback to a different color
		}

		var b bytes.Buffer
		err = formatter.Format(&b, styles.Get("monokai"), iterator)
		if err != nil {
			return au.BrightBlue(line).String() // Fallback on error
		}
		return b.String()
	}

	return au.BrightBlue(line).String()

	// Return non-SQL lines with log level colorized
	// return fmt.Sprintf("%s %s", au.Gray(12, timestamp), levelColorized)
}
