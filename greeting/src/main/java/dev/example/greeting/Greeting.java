package dev.example.greeting;

public final class Greeting {

    private Greeting() {
    }

    public static String hello(String name) {
        return "Hello, " + name;
    }
}
