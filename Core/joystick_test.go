package main

import (
	"bytes"
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestOffsetCoordinateMovesByMeters(t *testing.T) {
	lat, lon := offsetCoordinate(0, 0, 1, 1)
	metersPerDegree := earthRadiusMeters * math.Pi / 180
	if math.Abs(lat*metersPerDegree-1) > 0.001 {
		t.Fatalf("north offset = %f meters", lat*metersPerDegree)
	}
	if math.Abs(lon*metersPerDegree-1) > 0.001 {
		t.Fatalf("east offset = %f meters", lon*metersPerDegree)
	}
}

func TestJoystickRequestMovesEnabledLocation(t *testing.T) {
	stateMu.Lock()
	currentLat, currentLon, currentEnabled = 30, 120, true
	currentMotionSimulationEnabled = false
	joystickMotionUntil = time.Time{}
	stateMu.Unlock()

	body, _ := json.Marshal(joystickMoveRequest{EastMeters: 1, NorthMeters: 1, Moving: true})
	request := httptest.NewRequest(http.MethodPost, "/joystick", bytes.NewReader(body))
	response := httptest.NewRecorder()
	handleJoystickRequest(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	var result joystickMoveResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Latitude <= 30 || result.Longitude <= 120 || !result.MotionSimulationEnabled {
		t.Fatalf("unexpected response: %+v", result)
	}
}

func TestJoystickRequestRejectsLargeStep(t *testing.T) {
	body := []byte(`{"eastMeters":6,"northMeters":0,"moving":true}`)
	request := httptest.NewRequest(http.MethodPost, "/joystick", bytes.NewReader(body))
	response := httptest.NewRecorder()
	handleJoystickRequest(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d", response.Code)
	}
}
