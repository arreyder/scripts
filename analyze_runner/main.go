package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"time"

	_ "github.com/lib/pq"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

func main() {
	// Initialize OpenTelemetry exporter and tracer
	exporter, err := stdouttrace.New(stdouttrace.WithPrettyPrint())
	if err != nil {
		log.Fatalf("failed to initialize stdouttrace exporter: %v", err)
	}
	tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exporter))
	defer func() { _ = tp.Shutdown(context.Background()) }()
	tracer := tp.Tracer("postgresql-analyze")

	// Initialize zap logger
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	// Get environment variables
	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")

	if dbHost == "" {
		logger.Error("environment variable DB_HOST is not set")
	}
	if dbPort == "" {
		logger.Error("environment variable DB_PORT is not set")
	}
	if dbUser == "" {
		logger.Error("environment variable DB_USER is not set")
	}
	if dbPassword == "" {
		logger.Error("environment variable DB_PASSWORD is not set")
	}
	if dbName == "" {
		logger.Error("environment variable DB_NAME is not set")
	}

	if dbHost == "" || dbPort == "" || dbUser == "" || dbPassword == "" || dbName == "" {
		return
	}

	// Connect to the database
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable", dbHost, dbPort, dbUser, dbPassword, dbName)
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		logger.Fatal("failed to connect to the database", zap.Error(err))
	}
	defer db.Close()

	ctx := context.Background()
	ctx, span := tracer.Start(ctx, "analyze-tables")
	defer span.End()

	startTime := time.Now()

	// Fetch all tables that start with pb_
	rows, err := db.QueryContext(ctx, "SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'pb_%'")
	if err != nil {
		logger.Fatal("failed to fetch tables", zap.Error(err))
	}
	defer rows.Close()

	tables := make([]string, 0)
	for rows.Next() {
		var tableName string
		err = rows.Scan(&tableName)
		if err != nil {
			logger.Fatal("failed to scan table name", zap.Error(err))
		}
		tables = append(tables, tableName)
	}

	if err = rows.Err(); err != nil {
		logger.Fatal("failed to fetch tables", zap.Error(err))
	}

	for _, table := range tables {
		ctx, span := tracer.Start(ctx, "analyze-table", trace.WithAttributes(attribute.Key("table.name").String(table)))
		defer span.End()

		startTime := time.Now()

		query := fmt.Sprintf("ANALYZE %s", table)
		if _, err = db.ExecContext(ctx, query); err != nil {
			logger.Error("failed to analyze table", zap.String("table", table), zap.Error(err))
			continue
		}

		duration := time.Since(startTime).Seconds()
		logger.Info("analyzed table", zap.String("table", table), zap.Float64("duration_seconds", duration))

		// Emit metric
		// ...
	}

	duration := time.Since(startTime).Seconds()
	logger.Info("analyzed all tables", zap.Float64("duration_seconds", duration))

	// Emit metric
	// ...
}
