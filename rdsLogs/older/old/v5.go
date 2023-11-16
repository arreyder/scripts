package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/rds"
)

type LogMessage struct {
	Message string `json:"message"`
}

type State struct {
	LastFile string `json:"last_file"`
	Marker   string `json:"marker"`
}

// This function splits the log data into messages
func splitLogDataIntoMessages(logData string) []string {
	//	pattern := `[\d-]{10} [\d:]{8} UTC::@:\[\d*\]:LOG:`
	pattern := `^[\d-]{10} [\d:]{8} UTC:[^:]*:[^@]*@[^:]*:\[\d*\]:.*$|^[\d-]{10} [\d:]{8} UTC::@:\[\d*\]:LOG:.*$`

	re := regexp.MustCompile(pattern)

	lines := strings.Split(logData, "\n")

	var messages []string
	var currentMessage strings.Builder
	for _, line := range lines {
		line = strings.ReplaceAll(line, "\t", " ")
		if re.MatchString(line) {
			if currentMessage.Len() > 0 {
				messages = append(messages, currentMessage.String())
				currentMessage.Reset()
			}
			currentMessage.WriteString(line)
		} else {
			currentMessage.WriteString(" " + line)
		}
	}
	if currentMessage.Len() > 0 {
		messages = append(messages, currentMessage.String())
	}

	return messages
}

// This function loads the state from the local state file
func loadState() *State {
	state := &State{}
	stateFile, err := os.Open("state.json")
	defer stateFile.Close()
	if err == nil {
		decoder := json.NewDecoder(stateFile)
		err = decoder.Decode(state)
		if err != nil {
			log.Fatalf("Failed to decode state: %v", err)
		}
	}
	return state
}

// This function saves the state to the local state file
func saveState(state *State) {
	stateFile, err := os.Create("state.json")
	defer stateFile.Close()
	if err != nil {
		log.Fatalf("Failed to open state file: %v", err)
	}
	encoder := json.NewEncoder(stateFile)
	err = encoder.Encode(state)
	if err != nil {
		log.Fatalf("Failed to encode state: %v", err)
	}
}

func main() {
	sess, err := session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	})

	if err != nil {
		log.Fatalf("Failed to create session: %v", err)
	}

	dbInstanceIdentifier := os.Getenv("DB_INSTANCE_IDENTIFIER")
	if dbInstanceIdentifier == "" {
		log.Fatal("DB_INSTANCE_IDENTIFIER environment variable is not set")
	}

	svc := rds.New(sess)
	state := loadState()

	for {
		input := &rds.DescribeDBLogFilesInput{
			DBInstanceIdentifier: aws.String(dbInstanceIdentifier),
		}

		result, err := svc.DescribeDBLogFiles(input)
		if err != nil {
			log.Fatalf("Failed to describe DB log files: %v", err)
		}

		for _, file := range result.DescribeDBLogFiles {
			if state.LastFile != "" && *file.LogFileName != state.LastFile {
				continue
			}

			downloadInput := &rds.DownloadDBLogFilePortionInput{
				DBInstanceIdentifier: aws.String(dbInstanceIdentifier),
				LogFileName:          file.LogFileName,
				Marker:               aws.String(state.Marker),
			}

			downloadResult, err := svc.DownloadDBLogFilePortion(downloadInput)
			if err != nil {
				log.Fatalf("Failed to download DB log file portion: %v", err)
			}

			messages := splitLogDataIntoMessages(*downloadResult.LogFileData)
			for _, message := range messages {
				logMessage := LogMessage{
					Message: message,
				}

				jsonData, err := json.Marshal(logMessage)
				if err != nil {
					log.Fatalf("Failed to convert log message to JSON: %v", err)
				}

				fmt.Println(string(jsonData))
			}

			state.LastFile = *file.LogFileName
			state.Marker = *downloadResult.Marker
			saveState(state)
		}

		time.Sleep(5 * time.Minute)
	}
}
