#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <utility>

namespace {

constexpr int event_count = 5;

class Event {
public:
    explicit Event(int number)
        : number_(number), message_("Команда " + std::to_string(number)) {}

    int number() const {
        return number_;
    }

    void process() const {
        std::printf("Потребитель: обработал событие №%d (%s)\n",
                    number_, message_.c_str());
        std::fflush(stdout);
    }

private:
    int number_;
    std::string message_;
};

class Monitor {
public:
    bool provide(std::unique_ptr<Event> event) {
        std::unique_lock<std::mutex> lock(mutex_);

        condition_.wait(lock, [this] { return !event_ || stopping_; });
        if (stopping_) {
            return false;
        }

        event_ = std::move(event);
        std::printf("Поставщик: отправил событие №%d\n", event_->number());
        std::fflush(stdout);

        condition_.notify_one();
        return true;
    }

    bool consume() {
        std::unique_lock<std::mutex> lock(mutex_);

        condition_.wait(lock, [this] { return event_ || stopping_; });
        
        if (!event_) {
            return false;
        }

        auto event = std::move(event_);
        event->process();

        condition_.notify_one();
        return true;
    }

    void close() {
        std::lock_guard<std::mutex> lock(mutex_);
        stopping_ = true;
        condition_.notify_all();
    }

private:
    std::mutex mutex_;
    std::condition_variable condition_;
    std::unique_ptr<Event> event_;
    bool stopping_ = false;
};

bool run_producer(Monitor& monitor) {
    try {
        for (int number = 1; number <= event_count; ++number) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            if (!monitor.provide(std::make_unique<Event>(number))) {
                break;
            }
        }
    } catch (const std::bad_alloc&) {
        std::fputs("Поставщик: не удалось выделить память для события\n", stderr);
        monitor.close();
        return false;
    }

    monitor.close();
    return true;
}

void run_consumer(Monitor& monitor) {
    while (monitor.consume()) {
    }
}

}

int main() {
    Monitor monitor;
    std::thread consumer;
    std::thread producer;
    bool producer_succeeded = false;

    try {
        consumer = std::thread([&monitor] { run_consumer(monitor); });
        producer = std::thread([&monitor, &producer_succeeded] {
            producer_succeeded = run_producer(monitor);
        });
    } catch (const std::exception& error) {
        std::fprintf(stderr, "Не удалось запустить потоки: %s\n", error.what());
        monitor.close();
        if (consumer.joinable()) {
            consumer.join();
        }
        return EXIT_FAILURE;
    }

    producer.join();
    consumer.join();
    return producer_succeeded ? EXIT_SUCCESS : EXIT_FAILURE;
}
