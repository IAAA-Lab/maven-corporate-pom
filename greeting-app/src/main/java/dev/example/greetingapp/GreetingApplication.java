package dev.example.greetingapp;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

import dev.example.greeting.Greeting;

@SpringBootApplication
public class GreetingApplication {

    public static void main(String[] args) {
        SpringApplication.run(GreetingApplication.class, args);
    }

    @Bean
    CommandLineRunner greetingRunner() {
        return args -> System.out.println(Greeting.hello("Codespaces"));
    }
}
