# tests/test_acceptance_app.py
import os

import pytest
from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

BASE_URL = os.environ.get("APP_BASE_URL", "http://localhost:8000")

_SAMPLE_INPUT = {
    "CRIM": "0.00632",
    "ZN": "18.0",
    "INDUS": "2.31",
    "CHAS": "0",
    "NOX": "0.538",
    "RM": "6.575",
    "AGE": "65.2",
    "DIS": "4.09",
    "RAD": "1",
    "TAX": "296.0",
    "PTRATIO": "15.3",
    "B": "396.9",
    "LSTAT": "4.98",
}


@pytest.fixture
def browser():
    """Return a headless Chrome browser instance."""
    options = webdriver.ChromeOptions()
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    driver = webdriver.Chrome(options=options)
    yield driver
    driver.quit()


def _fill_and_submit(browser, input_data):
    """Fill all form fields with input_data and click submit."""
    for field_name, value in input_data.items():
        element = browser.find_element(By.NAME, field_name)
        element.clear()
        element.send_keys(value)
    browser.find_element(By.CSS_SELECTOR, "button[type='submit']").click()


def test_home_page_has_form(browser):
    """ACCEPTANCE: Home page loads and contains the prediction form."""
    browser.get(BASE_URL + "/")
    assert browser.find_element(By.TAG_NAME, "form") is not None


def test_prediction_result_appears(browser):
    """ACCEPTANCE: Submitting valid form data shows the result card."""
    browser.get(BASE_URL + "/")
    _fill_and_submit(browser, _SAMPLE_INPUT)
    try:
        WebDriverWait(browser, 10).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, ".result-card"))
        )
        result_text = browser.find_element(By.CSS_SELECTOR, ".result-card").text
        assert "$" in result_text or "32" in result_text
    except TimeoutException as exc:
        raise AssertionError(
            "Result card did not appear after form submission."
        ) from exc


@pytest.mark.parametrize(
    "field, value",
    [
        ("RM", "8.0"),
        ("RM", "4.0"),
    ],
)
def test_prediction_varies_with_input(browser, field, value):
    """ACCEPTANCE: Changing inputs produces a visible result on submission."""
    browser.get(BASE_URL + "/")
    modified = {**_SAMPLE_INPUT, field: value}
    _fill_and_submit(browser, modified)
    try:
        WebDriverWait(browser, 10).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, ".result-card"))
        )
    except TimeoutException as exc:
        raise AssertionError(
            f"Result card did not appear when {field}={value}."
        ) from exc
