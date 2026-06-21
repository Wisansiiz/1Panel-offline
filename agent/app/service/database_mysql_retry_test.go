package service

import (
	"errors"
	"testing"
)

func TestRetryRowsReturnsWhenDatabaseBecomesReady(t *testing.T) {
	attempts := 0
	rows, err := retryRows(3, 0, func() ([]string, error) {
		attempts++
		if attempts < 3 {
			return nil, errors.New("mysql is still starting")
		}
		return []string{"1"}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if attempts != 3 || len(rows) != 1 || rows[0] != "1" {
		t.Fatalf("unexpected retry result: attempts=%d rows=%v", attempts, rows)
	}
}

func TestRetryRowsReturnsLastError(t *testing.T) {
	expected := errors.New("mysql did not start")
	attempts := 0
	_, err := retryRows(2, 0, func() ([]string, error) {
		attempts++
		return nil, expected
	})
	if !errors.Is(err, expected) {
		t.Fatalf("expected last error, got %v", err)
	}
	if attempts != 2 {
		t.Fatalf("expected 2 attempts, got %d", attempts)
	}
}
