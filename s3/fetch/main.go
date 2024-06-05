package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
)

// downloadS3Objects downloads objects from S3 starting from the given path and stores them in the local directory.
func downloadS3Objects(bucket, s3Path, localDir string) error {
	sess, err := session.NewSessionWithOptions(session.Options{
		Config: aws.Config{
			Region: aws.String("us-east-2"),
		},
		SharedConfigState: session.SharedConfigEnable,
	})

	if err != nil {
		return fmt.Errorf("failed to create AWS session: %v", err)
	}

	svc := s3.New(sess)
	downloader := s3manager.NewDownloader(sess)

	if err := os.MkdirAll(localDir, 0755); err != nil {
		return fmt.Errorf("failed to create local directory: %v", err)
	}

	err = svc.ListObjectsV2Pages(&s3.ListObjectsV2Input{
		Bucket: &bucket,
		Prefix: &s3Path,
	}, func(page *s3.ListObjectsV2Output, lastPage bool) bool {
		for _, obj := range page.Contents {
			key := *obj.Key
			downloadPath := filepath.Join(localDir, strings.TrimPrefix(key, s3Path))
			fmt.Printf("Downloading %s to %s\n", key, downloadPath)

			if err := os.MkdirAll(filepath.Dir(downloadPath), 0755); err != nil {
				log.Printf("Unable to create directories for %s: %s", downloadPath, err)
				continue
			}

			f, err := os.Create(downloadPath)
			if err != nil {
				log.Printf("Unable to create file %s: %s", downloadPath, err)
				continue
			}

			_, err = downloader.DownloadWithContext(context.Background(), f, &s3.GetObjectInput{
				Bucket: aws.String(bucket),
				Key:    aws.String(key),
			})
			if err != nil {
				log.Printf("Unable to download file %s: %s", key, err)
			}
			f.Close()
		}
		return true
	})

	return err
}

func main() {
	bucket := "aws-cloudtrail-logs-c1-org-wide"
	s3Path := "AWSLogs/o-8jrnbufria/xxxxxxx/CloudTrail/ap-south-1/2023/12/" // S3 path to start from
	localDir := "./2023Dec"                                                 // Local directory to download files to

	if err := downloadS3Objects(bucket, s3Path, localDir); err != nil {
		log.Fatalf("Failed to download objects: %s", err)
	}
}
