package dev.example.greetingapp;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import dev.example.greeting.Greeting;

@SpringBootTest
class GreetingApplicationTest {

    @Test
    void usesTheVersionManagedGreetingLibrary() {
        assertEquals("Hello, Codespaces", Greeting.hello("Codespaces"));
    }
}
